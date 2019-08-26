#!/mu/bin/perl
#----------------------------  FILE INFORMATION  ----------------------------
#
# $URL: http://svn/mfg/probe/automation/perlmenu/trunk/carrier_edit/carrier_edit.pl $
# $Rev: 7702 $
# $Date: 2014-01-24 10:49:56 -0700 (Fri, 24 Jan 2014) $
# $Author: kylerobison $
#
#----------------------------  file information  ----------------------------
#-------------------------------  COPYRIGHT   -------------------------------
#
# ¨ 2007 Micron Technology, Inc. All Rights Reserved.
#
# THIS SOFTWARE CONTAINS CONFIDENTIAL INFORMATION AND TRADE SECRETS OF
# MICRON TECHNOLOGY, INC. USE, DISCLOSURE, OR REPRODUCTION IS PROHIBITED
# WITHOUT THE PRIOR EXPRESS WRITTEN PERMISSION OF MICRON TECHNOLOGY, INC.
#
#-------------------------------  Copyright   -------------------------------
#------------------------------  EXPORT NOTICE  -----------------------------
#
# These commodities, technology, or software were exported from the
# United States in accordance with the Export Administration Regulations.
# Diversion contrary to U.S. law is prohibited.
#
#------------------------------  export notice  -----------------------------

use File::Basename;
use File::Spec;

use lib File::Spec->catfile(dirname($0), '..', 'lib'); # in a relative dir
use lib dirname($0);         # or the same directory as this script
use lib '/u/probe/lib';
use lib '/u/prbsoft/lib';

use Tk;
use strict;
use Tk::SlotSelect;
use Data::Dumper;
use MTGroups;

use ProbeTrackInterface;
use Getopt::Long;
use XML::Parser;
use Data::Dumper;
use strict;
use Sys::Hostname;
use Tk::Dialog;
use MIPCSoap;
use HTML::Entities;          # to encode HTML entities (e.g. < is &lt;)
use Data::Dumper;

use constant FATAL=>0; # Displays a message box before exiting.
use constant ERROR=>1; # Normal error message.
use constant DEBUG=>2; # Stuff to print when running with the -debug option only
use constant INFO=>3;  # Information to pass to the operator

my %SITE_CFG = (
    'PrbTrack'  => {
       'BOISE'          => ['BOWPROBETRACK01', 'BOWPROBETRACK02', 'BOWPROBETRACK03'],
       'BOISE_3'        => ['/BOISE/MTI/MFG/PROBE/PROD/PRODUCTTRACKSRV/COMMAND/BALANCED'],
       'AVEZZANO'       => ['NTAZPROBE01', 'NTAZPROBE02', 'NTAZPROBE03'],
       'MANASSAS'       => ['MTV/MFG/PROBE/PROD/PRODUCTTRACKSRV/COMMAND/BALANCED'],
       'NISHIWAKI'      => ['SVCNIPRBA', 'SVCNIPRBB', 'SVCNIPRBC'],
       'TECH_SINGAPORE' => ['WAS3SPTSVC01.techsemi.com.sg', 'WAS3SPTSVC02.techsemi.com.sg', 'WAS3SPTSVC03.techsemi.com.sg'],
       'LEHI'           => ['SVCLEPRB1', 'SVCLEPRB2', 'SVCLEPRB3', 'SVCLEMESPOOL1'],
       'IMFS'           => ['SVCFSPRB1', 'SVCFSPRB2', 'SVCFSPRB3'],
    },
);

our ($SCRIPT_FILE, $BASEDIR, $SCRIPT_EXT) = fileparse($0, '.pl');
my $MESSAGE_FILE  = "imenu.i18n";
my $MESSAGE_PATH;
my %OPT;
my %carrier_definition;
my $w;
my %lmsg; # Local Messages

chdir ($BASEDIR);

GetOptions(
    \%OPT,
    'debug:s',       
    'site=s',
    'equip_id=s',
    'head=s',
	'offline',
	'lang=s',
);



# PLATFORM CONFIGURATION
# I could have read this from the imenu.config file, but I'm avoiding it
# because Tim is working on a restructure of menu

my ($traveler_path,$scribe_table_path,$daemon_interface_file_path);
my $daemon_interface_file_path;

if ($OPT{'lang'} eq 'jp') { # japaneese 
	$lmsg{'title'} = "jp:On-the-Fly Carrier Edit";
	$lmsg{'lbl_employee_number'} = "jp:Micron Employee Number";
	$lmsg{'lbl_modify_head'} = "jp:Modify Head";
	$lmsg{'lbl_cancel'} = "jp:Cancel";
	
} elsif ($OPT{'lang'} eq 'it') { # italian
	$lmsg{'title'} = "it:On-the-Fly Carrier Edit";
	$lmsg{'lbl_employee_number'} = "it:Micron Employee Number";
	$lmsg{'lbl_modify_head'} = "it:Modify Head";
	$lmsg{'lbl_cancel'} = "it:Cancel";
} else { # english
	$lmsg{'title'} = "On-the-Fly Carrier Edit";
	$lmsg{'lbl_employee_number'} = "Micron Employee Number";
	$lmsg{'lbl_modify_head'} = "Modify Head";
	$lmsg{'lbl_cancel'} = "Cancel";
}


if  (!defined $OPT{'equip_id'} and hostname() =~ /^(\w\w\d\w{7})/ ) {
	$OPT{'equip_id'} = $1;
} else {
	$OPT{'offline'} = 1;
}

if ( $OPT{'equip_id'} =~ /5400$/i ) {
    $traveler_path = "P:\\probe";
    $scribe_table_path = "p:/probe/lot_attr";
    $daemon_interface_file_path = "p:\\probe\\log\\daemon_interface";
    $MESSAGE_PATH = "p:\\probe\\menu\\$MESSAGE_FILE";
}
elsif ( $OPT{'equip_id'} =~ /(i750)$/i or $OPT{'equip_id'} =~ /(opmi)$/i){
	if ( hostname() =~ /kylerobison$/i or $OPT{'equip_id'} =~ /(opmi)$/i ) {
		$traveler_path = "C:\\probe";
		$scribe_table_path = "c:/probe/lot_attr";
		$daemon_interface_file_path = "c:\\probe\\log\\daemon_interface";
		$MESSAGE_PATH = "c:\\probe\\menu\\$MESSAGE_FILE";   
	}
	else {
		$traveler_path = "C:\\probe";
		$scribe_table_path = "c:/probe/lot_attr";
		$daemon_interface_file_path = "c:\\probe\\log\\daemon_interface";
		$MESSAGE_PATH = "c:\\probe\\menu\\$MESSAGE_FILE";   
	}
}
else 
{  
    if ( $OPT{'equip_id'} =~ /(viz)|(c1d)|(c2d)/i) {
        $scribe_table_path = "/u/product/job"; #valid for c1d,vizx
    }
	 else {
        $scribe_table_path = "/u/probe/lot_attr"; #valid for c1d,vizx
    }
    $daemon_interface_file_path = "/tmp/daemon_interface";
    $traveler_path = "/var/tmp";        
    if ( $OPT{'equip_id'} =~ /viz/i) {
        $MESSAGE_PATH = "/u/product/menu/$MESSAGE_FILE";
    } 
    else {
        $MESSAGE_PATH = "/u/probe/menu/$MESSAGE_FILE";
    }    
}

die "equip_id is not defined.  If not running on a tetser host you should provide -equip_id=<hostname>" if !defined($OPT{'equip_id'});

my $resource_class = 'Menu';
my $worker_no;
my $UNASSIGNED_SLOT = ' ';      # Things don't work well if this is an empty string.
my $EMPTY = 'Undef';            # Keyword indicating wafer is not present
our $EMPTY_SLOT = 'Empty';      # Keyword indicating no wafer is present in carrier slot
my %options = (
    'DataRework'   =>    'DataRework'    ,
    'Waiting'      =>    'Waiting'       ,
    'DataComplete' =>    'DataComplete'  ,
    'DataAborted'  =>    'DataAborted'   ,
    'Running'      =>    'Running'       ,
    'Processed'    =>    'Processed'     ,
    'Paused'       =>    'Paused'        ,
    'Error'        =>    'Error'         ,
    'Complete'     =>    'Complete'      ,
    'Aborted'      =>    'Aborted'       ,
    'SELECTED'     =>    'Committed'     ,
    'CORE'         =>    'CORE'          ,
    'REL'          =>    'REL'           ,
    'SWR'          =>    'SWR'           ,
); 

my %T;
my $attr_name;
my $attr_value;
my $wafer_id;
my $scribe_id;
my $error;
my %T; #Tags   
my %results;

if (-r $MESSAGE_PATH) {
    require $MESSAGE_PATH;
} else {
    $error =  "Can't find $MESSAGE_PATH";
}

Tk::CmdLine::LoadResources(
    -file => "imenu.resource",
    -priority => 'userDefault', # 'startupFile' is too low of priority to work with my settings
);

my $xml=XML::Parser->new(
    Handlers => 
    {
        Char => sub {
            
            my ($expat, $string) = @_;
            my @context = @{$expat->{'Context'}};
            my $context_str = join "/",@context;
            if ($T{Wafer}) {
                if ($attr_name eq 'WaferId') {
                    $wafer_id = $attr_value;
                }
                $results{$wafer_id}{'scribe'} = $scribe_id;

                if ($T{AttributeValue} and $T{AttributeValueList} ) {
                    if ($attr_name eq 'PROCESS STATE'){
                        $results{$wafer_id}{'process_state'} = $string;
                    }
                    elsif ($attr_name eq 'SLOT NUMBER') {
                        $results{$wafer_id}{'slot'} = $string;
                    }
                    elsif ($attr_name eq "PROGRAM RAN") {
                        $results{$wafer_id}{'program'} = $string;
                    }
                    elsif ($attr_name eq "PROGRAM REV ID") {
                        $results{$wafer_id}{'rev'} = $string;
                    }
                }
            }
        },
        Start=> sub {
            my ($expat, $element, %attrs) = @_;  
            $T{$element} = 1;   
            $attr_name = $attrs{'Name'};
            if ($element eq 'Wafer') {
                $wafer_id = $attrs{'WaferId'};
                $scribe_id = $attrs{'WaferScribeId'}; 
            }
        },
        End=> sub {
            my ($expat, $element, %attrs) = @_;
            delete $T{$element};
        },
    });

# site is required
if ($OPT{'site'})
{
    $OPT{'site'} = uc $OPT{'site'};
}
elsif ($ENV{'SITE_NAME'})
{
    $OPT{'site'} = uc $ENV{'SITE_NAME'};
}
else {
    $error = "SITE_NAME is not defined.";
}

my %EQUIPMENT;
my $MESSRV = 'MTI/MFG/MESSRV/PROD/SERVER/MESSRV';
my $FACILITY = 'FAB 3';
my $GROUP = 'PRB_TESTER_MAINFRAME';
my $AREA = 'F3 PROBE';

get_equip_state(\%EQUIPMENT, $OPT{'site'}, $MESSRV, $FACILITY, "<AreaId>$AREA</AreaId><GroupId>" . encode_entities($GROUP) . "</GroupId><EquipId>".uc($OPT{'equip_id'})."</EquipId>");

my %travelers;
# Get Active Travelers
foreach my $head ((0..1)) {
    foreach my $port (('front','rear')){
        my $file = File::Spec->catfile($traveler_path,"lot_traveler_h".$head."_".$port.".active"); 
        if (-e $file) {
            $travelers{$head} = get_file_attr_hash($file);
        } 
    }    
}

if (!scalar keys %travelers) {
	if ($OPT{'lang'} eq 'jp') {
		# japaneese
		$error = "jp:I could not find an active lot traveler file in \"".eval{$traveler_path}."\".  Use Menu to reintroduce the lot.";
	} elsif($OPT{'lang'} eq 'it') {
		# italian
		$error = "it:I could not find an active lot traveler file in \"".eval{$traveler_path}."\".  Use Menu to reintroduce the lot.";
	} else {
		# english
		$error = "I could not find an active lot traveler file in \"".eval{$traveler_path}."\".  Use Menu to reintroduce the lot.";
	}
}
elsif (defined $travelers{0} and defined $travelers{1}  and $travelers{0}{'LOT'} eq $travelers{1}{'LOT'}) {

	if ($OPT{'lang'} eq 'jp') {
		# japaneese
		$error = "jp:Your lot appears to be split on two heads.  You can not edit split carrier Maps.\n"
	} elsif($OPT{'lang'} eq 'it') {
		# italian
		$error = "it:Your lot appears to be split on two heads.  You can not edit split carrier Maps.\n"
	} else {
		# english
		$error = "Your lot appears to be split on two heads.  You can not edit split carrier Maps.\n"
	}
}

my $mw = MainWindow->new(-class => 'Menu',        
                         -title => "$lmsg{'title'}",      
                         );
if ($error) {
    notify(FATAL,$error);
    exit;
}    
$mw->Label(-text => $lmsg{'lbl_employee_number'})->pack( );
my $entry = $mw->Entry(
            -invalidcommand  => sub {$mw->bell},
            -validate => 'all', 
            -textvariable => \$worker_no,
            -validatecommand => \&tk_validate_num,
        )->pack(-pady=>5);
        
my $small_font = $mw->fontCreate( -size => 9);


$mw->bind('all' => '<Key-Escape>' => sub {exit;});
my $buttons = $mw->Frame()->pack();
my $warning = $mw->Label( -font => $small_font, 
                          -width   => 60,
                          -relief =>  'sunken'
                        )->pack();
$buttons->Button(-text=>$lmsg{'lbl_cancel'}, -command => sub{exit})->pack(-side => 'right', -padx=>5, -pady=>5);
if (defined $travelers{1}) {
    $buttons->Button(-text=>"$lmsg{'lbl_modify_head'} B", -command => [\&show_carrier,$entry,$mw,1],)->pack(-side => 'right', -padx=>5, );
}
if (defined $travelers{0}) {
    $buttons->Button(-text=>"$lmsg{'lbl_modify_head'} A", -command => [\&show_carrier,$entry,$mw,0],)->pack(-side => 'right', -padx=>5, );
}

my %protected_states = ( 'TEST_ENG'   => ['Processed','DataAborted','Running'],
                         'UP_PRODUCT' => ['Processed','DataComplete','DataAborted','Running'],
                       );     

$mw->overrideredirect(0);
$mw->raise;
$entry->focus;
MainLoop();

 
sub get_process_states{    
    my ($xml_str) = @_;
    $xml->parse($xml_str);    
    return (\%results);
}

sub show_carrier 
{
    my ($entry,$mw,$head) = @_; 
    my $username;
    my $status = MTGroupWorkerNoToUsername ( $worker_no , $username );              # Validate worker Number
    if (!$status or  !$worker_no) {	
		if ($OPT{'lang'} eq 'jp') {
			# japaneese
			notify(ERROR,"jp:Not a valid Micron Number");
		} elsif($OPT{'lang'} eq 'it') {
			# italian
			notify(ERROR,"it:Not a valid Micron Number");
		} else {
			# english
			notify(ERROR,"Not a valid Micron Number");
		}
        return;
    }    
    my $carrier_copy;
    my $lot_id = $travelers{$head}{'LOT_ID'};
    my $pid = $travelers{$head}{'PROCESS_ID'};
    my $filename = "$scribe_table_path/scribe_table_hd$head.out";
    if (open FILE, $filename ) {
        chomp(my $line = <FILE>);
        my ($lot) = ($line =~ /(\S+$)/);
        while (<FILE>) {
            my ($scribe,$wafer_no,$start_lot_key,$lot,$state,undef,$expected_slot,$actual_slot) = ($_ =~ /(\S+):\s+(\S{7}):\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+S(\S+)\s+S(\S+)/);
            if ($actual_slot and $expected_slot != $actual_slot) {
                notify(FATAL,"The Probe Tracking carrier map does not match the actual cassette map.  On the fly edits are not possible unless this is resolved."); # localize
            }         
             
             # populate carrier definition from scribe table
            $carrier_definition{$expected_slot}{'WaferId'} = $wafer_no;
            $carrier_definition{$expected_slot}{'WaferScribe'} = $scribe;            
            $carrier_definition{$expected_slot}{'Context'} = "$wafer_no: ";   
            if ($state =~ /PROCESSED/i) {
                $carrier_definition{$expected_slot}{'WaferState'} = 'Processed';
            }
            elsif ($state =~ /NEEDS_PROCESSING/i) {
                $carrier_definition{$expected_slot}{'WaferState'} = 'Committed';
            }
            elsif ($state =~ /IN_PROCESS/i) {
                $carrier_definition{$expected_slot}{'WaferState'} = 'Running';
            }         
            else {
                $carrier_definition{$expected_slot}{'WaferState'} = $state;
            }
        }
        close FILE;
    }
    else {		
        notify(FATAL,PrbLocale::file_open_fail($filename, 'read', "scribe table."));
    }
    
    notify(INFO, $PrbLocale::Msg{'calling_pattr'});
    $mw->update;
    my ($status, $reply) = GetProcessDataPackage($OPT{'site'}, $lot_id, $pid, undef, @{$SITE_CFG{'PrbTrack'}{$OPT{'site'}}});
    #print( Data::Dumper->Dump([$reply], [qw(*reply)]));
    if ($status) {
        notify(FATAL,$status); 
    }
    else
    {
        notify(INFO, "");
    }
    $mw->update;     
    my ($states_ref) = get_process_states($reply);   
	#print( Data::Dumper->Dump([$states_ref], [qw(*states_ref)]));
   
    my %carrier_copy;
    foreach my $slot (keys %carrier_definition) {    
        # populate DataCompletes from ProbeTracking.
        my $wafer_id = $carrier_definition{$slot}{'WaferId'};
        if ($carrier_definition{$slot}{'WaferState'} =~ /Processed/i and $states_ref->{$wafer_id}{'process_state'} =~ /DataComplete/)  {
            $carrier_definition{$slot}{'WaferState'} = 'DataComplete';
        }
        # preserve a deep copy to compare against.
        foreach my $carrier_item (keys %{$carrier_definition{$slot}}) {
            $carrier_copy{$slot}{$carrier_item} = $carrier_definition{$slot}{$carrier_item};
        }

    }
    
    $mw->withdraw(); 
    my $et_state;
    foreach my $level1 (keys %EQUIPMENT){
        foreach my $level2 (keys %{$EQUIPMENT{$level1}}){
            $et_state = $EQUIPMENT{$level1}{$level2}{'csubstate'}[$head];
            last;
        }
    }
    
	if (!defined $protected_states{$et_state}) {
		notify(FATAL,"$et_state is not recognized as a valid ET state for carrier editing");  # localize
	}
	
    print "\$et_state = $et_state\n" if $OPT{'debug'};
    $w = $mw->SlotSelect(
                -slotoptions => \%options,
                #-title        => 'carrier_title',
                -label        => 'wafer_select',
                -lcount       => $PrbLocale::Msg{'wafer_count'},
                -lfirst       => $PrbLocale::Msg{'choose_first'},
                -llast        => $PrbLocale::Msg{'choose_last'},
                -lrandom      => $PrbLocale::Msg{'choose_random'},
                -lall         => $PrbLocale::Msg{'choose_all'},
                -lnone        => $PrbLocale::Msg{'choose_none'},
                -empty        => $EMPTY_SLOT,
                -unassigned   => $UNASSIGNED_SLOT,
                -singlechoice => 'SELECTED',
                -protected   =>  \@{$protected_states{$et_state}},
                -viewonly   => 0,
                -order      => 'descending',
                -carrier    => \%carrier_definition,
    );      
    print "SlotSelect Called\hn" if $OPT{'debug'};
    
    $w->transient();         
    my $result = $w->Show();                    # Blocking Call to show slot selection mega widget        
    $w->destroy();
	
	#print( Data::Dumper->Dump([\%carrier_definition], [qw(*carrier_definition)]));
	
    my $buffer;
	my @commit_scribes;
    if ($result =~ /^O/i) { # OK button was pressed
        foreach my $slot (keys %carrier_definition) {
            if ($carrier_copy{$slot}{'WaferState'} =~ /Committed/) {  # Committed is the only state that accepts skip
																	  #  need to check this.  I think TEST_ENG allows more states.
                if (    $carrier_definition{$slot}{'WaferState'} ne $carrier_copy{$slot}{'WaferState'} and                     
                        $carrier_definition{$slot}{'WaferState'} !~ /\S/ ) {
                    $buffer .= "SKIP $carrier_definition{$slot}{'WaferScribe'}\n";
                }
            }
            else {
                if ( $carrier_definition{$slot}{'WaferState'} ne $carrier_copy{$slot}{'WaferState'} and 
                     $carrier_definition{$slot}{'WaferState'} =~ /Committed/i ) {
                    $buffer .= "REPROBE $carrier_definition{$slot}{'WaferScribe'}\n";
                }            
            }
			
			if ($carrier_definition{$slot}{'WaferState'} =~ /Committed/) {
				push @commit_scribes, $carrier_definition{$slot}{'WaferScribe'};
			}
        }
		if ($OPT{'offline'}) {
			print "Offline mode. Skipping wafer commits\n";
		}
		else {
            my ($status, $reply) = ProbeProcessCommit($OPT{'site'}, $lot_id, $travelers{$head}{"STATION_NAME"}, $pid, $travelers{$head}{"RUN_ID"}, join(',',@commit_scribes), $travelers{$head}{"PROGRAM"}, @{$SITE_CFG{'PrbTrack'}{$OPT{'site'}}});
            if ($status) {
                notify(FATAL,"Wafer Commit Error:$status");  # localize
            }
		}
		
        if ($buffer) {            
            if (open(FILE,">$daemon_interface_file_path$head")) {
                print FILE "OPERATOR $username\n".$buffer;
                close FILE;
            }
            else {
                notify(FATAL,"Could not write to $daemon_interface_file_path$head");   # localize
            }
        }
    }
    
    $mw->destroy;  # Exit message loop of main window.
}

# Validate the key strokes to make sure only number digits are used
sub tk_validate_num
{
    my ($value) = @_;
    if ($value =~ /^\d*$/) {
        #$warning->packForget();
        $warning->configure(-text => "");
        return 1;
    } else {
        return 0;
    }
}

#grab an attr hash from an attr file
sub get_file_attr_hash {
    my $file = shift;
    my %attr_hash;
    my $name;
    my $value;
    open FILE,$file;
    while (<FILE>) {
        if($_ =~ /(\w+):\s*(.+?)\s*?$/){
        $name = $1;
        $value = $2;
        $attr_hash{$name}=$value;
        }
    }
    return \%attr_hash;
}

sub notify {
    my ($mode,$message) = @_;   
    if ($mw) {    
        if ($mode == ERROR) {
            $mw->bell; 
            $warning->configure(-foreground => 'red');
        }        
        elsif ($mode == FATAL) {
            $mw->bell;            
            $mw->deiconify( );  # Make sure the main window is visable or the dialog won't display.
            $mw->raise( );
            my $d=$mw->Dialog(-title => "$lmsg{'title'}", -text => "$message");
            $d->Show;                 
            exit;
        }        
        else {
           $warning->configure(-foreground => 'black');
        }
        $warning->pack();
        $warning->configure(-text => "$message");
    } 
    else {
        if ($mode == DEBUG and !$OPT{'debug'} ) {
            return;
        }
        print $message."\n";
    }
}

