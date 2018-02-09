# --
# Copyright (C) 2001-2018 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

use strict;
use warnings;
use utf8;

use vars (qw($Self));

my $Selenium = $Kernel::OM->Get('Kernel::System::UnitTest::Selenium');

$Selenium->RunTest(
    sub {

        my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');

        # Do not check RichText.
        $Helper->ConfigSettingChange(
            Valid => 1,
            Key   => 'Frontend::RichText',
            Value => 0
        );

        # Create test user and login.
        my $TestUserLogin = $Helper->TestUserCreate(
            Groups => [ 'admin', 'users' ],
        ) || die "Did not get test user";

        $Selenium->Login(
            Type     => 'Agent',
            User     => $TestUserLogin,
            Password => $TestUserLogin,
        );

        # Get test user ID.
        my $TestUserID = $Kernel::OM->Get('Kernel::System::User')->UserLookup(
            UserLogin => $TestUserLogin,
        );

        my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

        # Create test ticket.
        my $TicketID = $TicketObject->TicketCreate(
            Title        => 'Selenium Test Ticket',
            Queue        => 'Raw',
            Lock         => 'unlock',
            Priority     => '3 normal',
            State        => 'new',
            CustomerID   => 'SeleniumCustomer',
            CustomerUser => 'SeleniumCustomer@localhost.com',
            OwnerID      => $TestUserID,
            UserID       => $TestUserID,
        );

        $Self->True(
            $TicketID,
            "Ticket is created - $TicketID",
        );

        my $ScriptAlias = $Kernel::OM->Get('Kernel::Config')->Get('ScriptAlias');

        # Navigate to zoom view of created test ticket.
        $Selenium->VerifiedGet("${ScriptAlias}index.pl?Action=AgentTicketZoom;TicketID=$TicketID");

        # Test for bug#11205 (http://bugs.otrs.org/show_bug.cgi?id=11205).
        # Check screen size to open popup according to available screen height.
        # Open popup with default height.
        # After that open popup with adjusted height.
        my $ParentWindowHeight = $Selenium->get_window_size()->{"height"};

        # Force sub menu to be visible in order to be able to click one of the links.
        $Selenium->WaitFor( JavaScript => "return typeof(\$) === 'function'" );
        $Selenium->execute_script("\$('#nav-Communication-container').css('height', 'auto')");
        $Selenium->execute_script("\$('#nav-Communication-container').css('opacity', '1')");
        $Selenium->WaitFor(
            JavaScript =>
                "return \$('#nav-Communication-container').css('height') !== '0px' && \$('#nav-Communication-container').css('opacity') == '1'"
        );

        # Click on 'Note' and switch window.
        $Selenium->find_element("//a[contains(\@href, \'Action=AgentTicketNote;TicketID=$TicketID' )]")->click();

        $Selenium->WaitFor( WindowCount => 2 );
        my $Handles = $Selenium->get_window_handles();
        $Selenium->switch_to_window( $Handles->[1] );

        # Wait until page has loaded, if necessary.
        $Selenium->WaitFor(
            JavaScript =>
                'return typeof($) === "function" && $(".WidgetSimple").length;'
        );

        my $PopupWindowHeight = $Selenium->execute_script(
            "return \$(window).height();"
        );

        $Self->Is(
            $PopupWindowHeight,
            700,
            "Default popup window height"
        );

        # Close note window.
        $Selenium->find_element( ".CancelClosePopup", 'css' )->click();
        $Selenium->WaitFor( WindowCount => 1 );

        # Switch window back to agent ticket zoom view of created test ticket.
        $Selenium->switch_to_window( $Handles->[0] );

        # Now try to open a popup with a height larger than the screen height (1000)
        # adjust PopupProfile for that.
        $Selenium->execute_script(
            "Core.UI.Popup.ProfileAdd('Default', { WindowURLParams: 'dependent=yes,location=no,menubar=no,resizable=yes,scrollbars=yes,status=no,toolbar=no', Left: 100, Top: 100, Width: 1040, Height: 1700 });"
        );

        # Force sub menu to be visible in order to be able to click one of the links
        $Selenium->WaitFor( JavaScript => "return typeof(\$) === 'function'" );
        $Selenium->execute_script("\$('#nav-Communication-container').css('height', 'auto')");
        $Selenium->execute_script("\$('#nav-Communication-container').css('opacity', '1')");
        $Selenium->WaitFor(
            JavaScript =>
                "return \$('#nav-Communication-container').css('height') !== '0px' && \$('#nav-Communication-container').css('opacity') == '1'"
        );

        # Click on 'Note' and switch window.
        $Selenium->find_element("//a[contains(\@href, \'Action=AgentTicketNote;TicketID=$TicketID' )]")->click();

        $Selenium->WaitFor( WindowCount => 2 );
        $Handles = $Selenium->get_window_handles();
        $Selenium->switch_to_window( $Handles->[1] );

        # Wait until page has loaded, if necessary.
        $Selenium->WaitFor(
            JavaScript =>
                'return typeof($) === "function" && $(".WidgetSimple").length;'
        );

        $PopupWindowHeight = $Selenium->execute_script(
            "return \$(window).height();"
        );

        $Self->True(
            $ParentWindowHeight - $PopupWindowHeight,
            "Popup window height ("
                . $PopupWindowHeight
                . "px) fits into screen height ("
                . $ParentWindowHeight
                . "px), even if defined larger"
        );

        # Delete created test tickets.
        my $Success = $TicketObject->TicketDelete(
            TicketID => $TicketID,
            UserID   => $TestUserID,
        );

        # Ticket deletion could fail if apache still writes to ticket history. Try again in this case.
        if ( !$Success ) {
            sleep 3;
            $Success = $TicketObject->TicketDelete(
                TicketID => $TicketID,
                UserID   => $TestUserID,
            );
        }
        $Self->True(
            $Success,
            "Ticket is deleted - ID $TicketID"
        );

        # Make sure the cache is correct.
        $Kernel::OM->Get('Kernel::System::Cache')->CleanUp(
            Type => 'Ticket',
        );
    }
);

1;
