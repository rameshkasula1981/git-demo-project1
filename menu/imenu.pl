#!/mu/bin/perl

#----------------------------  FILE INFORMATION  ----------------------------
#
my ($SVN_URL) = '$URL: http://svn/mfg/probe/automation/perlmenu/trunk/imenu.pl $' =~ /URL: (.+) \$/;
my ($SVN_VER) = '$Rev: 8358 $' =~ /Rev: (\d+)/;
# $Date: 2018-04-25 10:07:44 -0600 (Wed, 25 Apr 2018) $
# $Author: kbremkes $
#
#----------------------------  file information  ----------------------------

#-------------------------------  COPYRIGHT   -------------------------------
#
# © 2006-2013 Micron Technology, Inc. All Rights Reserved.
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

# Refer to ProbeLotIntroMenuAdminGuide.doc
# http://edm.micron.com/cgi-bin/mtgetdoc.exe?itemID=09005aef837aa3af

use lib qw(/home/probeng/PrbApps/lib/perl58/lib/); # for MJP, updated Tk libraries
# Perl and Micron Modules
use Tk;
use Tk::LabFrame;
use Tk::ROText;
use Tk::BrowseEntry;
use utf8;
use Encode;
use File::Basename;
use File::Spec;
use File::Path;      # mkpath, rmtree
use File::stat;
use File::Copy;
use File::Slurp;     # read_file, write_file
use Cwd;             # alternative to File::Spec->curdir that works
use Sys::Hostname;
use Getopt::Long;
use Carp;
use strict;
use warnings;
use Micron::MTGroups::CMTWorker;  # operator lookup
use Micron::Mail;                 # for important issue notification
use Micron::Page;                 # for important issue notification
use Data::Dumper;                 # for debug
use Text::ParseWords;             # quotewords, parse_line
use HTML::Entities;               # for decoding HTML
use XML::Parser;                  # this is for stream parsing of XML
use MTGroups;
$Data::Dumper::Sortkeys = 1;      # Sort hash keys in Dumper debug output
$Data::Dumper::Deepcopy = 1;      # show references to the same structure

# Global paths
our ($SCRIPT_FILE, $BASEDIR, $SCRIPT_EXT) = fileparse($0, '.pl');
use lib '/home/prbsoft/lib'; # modules can be in a well known location
use lib File::Spec->catfile(dirname($0), '..', 'lib'); # in a relative dir
use lib dirname($0);         # or the same directory as this script

# Probe Modules
use MESInterface;
use MIPCSoap;
use ProbeTrackInterface;
use Tk::SlotSelect;

# Globals
my $MAJOR_VER = '4';
my $MINOR_VER = '2';
our $MENU_VERSION = join('.', $MAJOR_VER,$MINOR_VER,$SVN_VER);
my $MESSAGE_FILE  = "${SCRIPT_FILE}.i18n";
my $CONFIG_FILE   = "${SCRIPT_FILE}.config";
my $RESOURCE_FILE = "${SCRIPT_FILE}.resource";
my $MESSAGE_PATH  = File::Spec->catfile($BASEDIR, '..', 'i18n', $MESSAGE_FILE);
my $CONFIG_PATH   = File::Spec->catfile($BASEDIR, '..', 'config', $CONFIG_FILE);
my $RESOURCE_PATH = File::Spec->catfile($BASEDIR, '..', 'config', $RESOURCE_FILE);
my $LOG_DIR;                    # platform specific path for application logging
my $LOG_FILE;                   # application log file
my $WARN_FILE;                  # application warnings file, for all notify('warn') 
my $CACHE_DIR;                  # platform specific path for network fault tolerance
my $JOB_RELEASE_SERVER;         # platform specific path to release server
my $MOVE_TABLE_SERVER;          # platform specific path to release server
my $LOCAL_JOB_DIR;              # platform specific local path
my $LOCAL_MOVE_TABLE_DIR;       # platform specific local path
my $LOCAL_JOB_ARCHIVE_DIR;      # platform specific local path
my $JOB_META_DIR;               # legacy path used by previous menu
my $MAX_JOB_AGE_DAYS;           # platform specific, jobs will be deleted if not accessed
my $PROBER_PACK_ORDER = 'left'; # over-ride with -b_left command option
my $FRONT_CASSETTE_LABEL;       # value depends on dual cassette capability
my $DEVIATION_LABEL;            # empty or localized string for engineering deviation
my $NEXT_SCREEN_LABEL;          # localized string indicating "Next" screen or "Start"
my $ON_HOLD_WAFERS;             # empty or localized string for on-hold warning
my $SCRAPPED_WAFERS;            # empty or localized string for scrapped wafer warning
my $LOCAL_OPERATION_MSG;        # empty or localized string for reduced network capability
my $NEW_TEST_JOB_MSG;           # empty or localized string for new test job
my $NEW_MOVE_TABLE_MSG;         # empty or localized string for new move table
my $LOCAL_OPERATION_OK;         # yes/no confirmation of network issues
our $UPDATE_TEST_JOB;           # yes/no to update test job
my $UPDATE_MOVE_TABLE;          # yes/no to update move table
my $NEW_TEST_JOB_PATH;          # fully qualified path on release server
my $NEW_MOVE_TABLE_PATH;        # fully qualified path on release server
my $PROBE_ON_HOLD;              # yes/no to probe on-hold lot
my $PROBE_SCRAPPED;             # yes/no to probe scrapped wafers
our $TESTER_ID;                 # obtained from hostname
our $OPERATOR_ID;               # entered by user
our $OPERATOR_NAME;             # obtained from CMTWorker
our $EMPLOYEE_NAME;             # obtained from CMTWorker
our $DESIGN_ID;                 # from MES
our $STEP_NAME;                 # from MES
my $ENGR_REQUEST;               # entered by user, input parameter to GeRM
our $REQUEST;                   # sent to GeRM to resolve exceptions based on Engineering Request
my %EQUIP_STATE_ALLOW;          # specifies which options are enabled based on SEMI-E10 States
my $GERM_PID_EXPECTED;          # true will read Data Collection Process ID from GeRM
my $BSC_MODE;                   # lot(s) staged using Batch Stage Controller
my $AUTO_START;                 # lot(s) staged using Batch Stage Controller and no operator required
our $JOB_NAME;                  # test job name w/o path, rev, timestamp
our $LOCAL_JOB_PATH;            # fully qualified local path to test job
our $MOVE_TABLE;                # move table name w/o path, rev, timestamp
our $TEMPERATURE;               # wafer chuck temperature setpoint
my $CURRENT_STATE;              # probing, idle, ...
our $EMPTY_SLOT = 'Empty';      # keyword indicating no wafer is present in carrier slot
my $UNASSIGNED_SLOT = '';       # keyword indicating a slot is available for assignment
our $PROBE_FACILITY;            # required in datalog
our $DEBUG_MODE;                # debugging this application
our $OVERRIDE_REASON;           # reason GeRM is over-ridden
our $NEW_JOB;                   # flag indicating that a new test job has been downloaded
my $ENCODING;                   # encoding for non-utf8 systems
our $GERM_PROCESS;              # GeRM process from GeRM or Batch Stage Controller
our $GERM_RECIPE;               # GeRM recipe name from GeRM or Batch Stage Controller
our $ALLOW_MIXED_REV_RECOVERY;  # from GeRM INTERRUPT_REV_UPDATE
our $REPROBE_ALLOWED;           # from GeRM REPROBE_ALLOWED
our $INTERRUPT_RECOVERY;        # determined from Probe Process Attributes
our $PREV_TEST_JOB_PATH;        # in a recovery scenario this is the path to the test job used for previously tested wafers.  undef if more than one.
our $PREV_TEST_JOB_REV;         # in a recovery scenario this is the test job rev used for previously tested wafers.  (MIXED if more than one)
our $PREV_TEST_JOB_MSG;         # empty or localized string for previous test job
our $PCONTROLEVENT;             # used to push menu alarms to ET
my @GERM_EXCEPTION_NAMES;       # list of exception recipe names returned from GeRM
my %PROCESS;                    # entered by user, or read from probe tracking
our %PROCESS_STEP;              # from GeRM
our %ET_ITEMS;                  # from ET
our %ET_STATE;                  # from ET
my %BATCH_LIST;                 # all batches staged to this equipment
our %PRB_LOT_META;              # from probe attribute server (deprecated)
our %PRB_LOT_ATTR;              # from probe tracking server
our %PRB_WFR_META;              # from probe tracking server (waferId - scribe lookup)
our %PRB_WFR_ATTR;              # from probe tracking server
our %PRB_PROCESS_ATTR;          # from probe tracking server
our %PRB_PROCESS_STATE;         # from probe tracking server
our %PRB_RETICLE_HISTORY;       # from probe tracking server
our %PRB_PART_ATTR;             # from probe tracking server
our %MES_ATTR;                  # from MES
our %MES_META;                  # from MES
my %PROCESS_LIST;               # from probe tracking
our %PCARD_ID;                  # from prober
our %PCARD_DATA;                # from PCT
my %PCARD_SUMMARY;              # information displayed to user about a card
our %LOAD_PORT;                 # information regarding where a lot is placed
our %CARRIER_USER_COPY;         # carrier that may be edited by user or by platform config file
our %GERM_LOT_DETAIL;           # only available if we route through MESSRV, not possible at this time
our %GERM_LOT_INFO;             # from GeRM
our %GERM_EQUIP_PARAM;          # from GeRM
our %GERM_EQUIP_META;           # from GeRM
our %GERM_PRB_LOT_ATTR;         # from GeRM - substitute for probe lot attributes
my $INSTRUCTIONS;               # from GeRM
our %OVERRIDE;                  # from user - substitute for GeRM parameters
our %RECIPE;                    # from GeRM or over-ride (Not Lot Or Head Specific)
# use of %PROBER_RECIPE is deprecated, important values will be duplicated in %LOAD_PORT to
# support dual headed and cascading of lots
our %PROBER_RECIPE;             # prober recipe parameters, likely from GeRM, possibly move table
our %MOVE_TABLE_INFO;           # summary of what is available in the move table
our %CASCADE_INFO;              # if we are adding to existing setup, parameters that must match
our %SLOT_ASSIGNMENTS;          # key is localized for user, value is slot assignment
our %OPT = ();                  # command line options
my %W;                          # Tk Widgets
our %TIMING_STATS;              # for performance tuning/monitoring
my %REQUIRE_CARRIER_VIEW;       # over-ride requires operator to view/edit all Carrier Maps
my $OLD_BROWSE_ENTRY = $Tk::BrowseEntry::VERSION =~ m/^[0-3]/; # prior to major rev 4, itemconfigure is not available
# these Global constants should not change between sites
my $MESSRV = 'MTI/MFG/MESSRV/PROD/SERVER/MESSRV';
my $PCTSRV = 'MTI/MFG/ESSOFTWARE/PROBE_CARD_TRACKING/PROD/DB_Server';
my $PCTSRVXML = 'PROBE_TEST_CENTRAL_SOFTWARE/PROBE_CARD_TRACKING/PROD/SSXML_MESSAGING';
my @EXCLUDE_MODES = ('ABORT', 'ENGINEERING RESTORE', 'PRODUCTION RESTORE', 'CORRELATE RESTORE', 'NONPROD RESTORE');
my $PRB_GERM_PROCESS_CORR_ITEM   = 47618;  # for setting MES Lot attributes
my $PRB_GERM_RECIPE_CORR_ITEM    = 47619;  # for setting MES Lot attributes
my $PRB_JOB_GERM_NAME_CORR_ITEM  = 138544; # for setting MES Lot attributes
my $PRB_JOB_GERM_REV_CORR_ITEM   = 138478; # for setting MES Lot attributes

# per djlopez this Tracking Step is available at all sites, it's purpose is
# to allow data collection using any Data Collection Process ID
# it is often used in combination with an Engineering Request
# if a lot is at this step, this script will attempt to read the correct
# Data Collection Process ID from GeRM
my $TRACKING_REQUEST_STEP = '9880-REQUEST PROBE';
# some equipment like the scrubber, laser, and PMI inspect tool do not have probecards
# this will be set by specifying -cardS=none
my $NO_PROBECARD;
# some equipment currently does not have child equipment
my $NO_CHILD_EQUIPMENT;
# if lots are staged and/or dispositioned off station
# or if material is delivered automatically
# tracking the operator placing or removing the lot is not needed
my $NO_OPERATOR_REQUIRED;
# to assist with Menu re-architecture
our @FUNCTION_TRACE;

# these settings should be good for all Micron sites and joint ventures
# I don't think they will change too often, so they are here rather than
# a configuration file
my %SITE_CFG = (
    'Facility'  => {
       'BOISE'          => 'F3 PROBE',
       'BOISE_2'        => 'TEST',
       'BOISE_3'        => 'FF ASSEMBLY',
       'AVEZZANO'       => 'F9 PROBE',
       'MANASSAS'       => 'F6 PROBE',
       'NISHIWAKI'      => 'F0 PROBE',
       'TECH_SINGAPORE' => 'F7 PROBE',
       'LEHI'           => 'F2 PROBE',
       'IMFS'           => 'F10 PROBE',
       'TAOYUAN'        => 'F11 PROBE',
       'HIROSHIMA'      => 'F15 PROBE',
       'TAICHUNG'       => 'F16 PROBE',
    },
    'GeRMFacility'  => {
       'BOISE'          => 'FAB 3',
       'BOISE_3'        => 'FAB F',
       'AVEZZANO'       => 'FAB 9 (MIT)',
       'MANASSAS'       => 'FAB 6',
       'NISHIWAKI'      => 'FAB 0',
       'TECH_SINGAPORE' => 'FAB 7',
       'LEHI'           => 'FAB 2',
       'IMFS'           => 'FAB 10',
       'TAOYUAN'        => 'FAB 11',
       'HIROSHIMA'      => 'FAB 15',
       'TAICHUNG'       => 'FAB 16',
    },
    'PrbTrack'  => {
       # if you specify an MIPC subject (vs. a Peer-Peer host) that ends in COMMAND
       # you should probably repeat the address more than once, if you don't
       # there is no benefit in using that subject because message negotiation
       # will be disabled
       # if you specify only one address, it should probably end in BALANCED, see ProbeTrackInterface
#       'BOISE'          => ['/BOISE/MTI/MFG/PROBE/PROD/PRODUCTTRACKSRV/COMMAND/BALANCED'],
       'BOISE'          => ['BOWPROBETRACK01', 'BOWPROBETRACK02', 'BOWPROBETRACK03'],
       'BOISE_3'        => ['/BOISE/MTI/MFG/PROBE/PROD/PRODUCTTRACKSRV/COMMAND/BALANCED'],
       'AVEZZANO'       => ['NTAZPROBE01', 'NTAZPROBE02', 'NTAZPROBE03'],
       'MANASSAS'       => ['MTV/MFG/PROBE/PROD/PRODUCTTRACKSRV/COMMAND/BALANCED'],
       'NISHIWAKI'      => ['SVCNIPRBA', 'SVCNIPRBB', 'SVCNIPRBC'],
       'TECH_SINGAPORE' => ['WAS3SPTSVC01.wlsg.micron.com', 'WAS3SPTSVC02.wlsg.micron.com', 'WAS3SPTSVC03.wlsg.micron.com'],
#       'TECH_SINGAPORE' => ['WAS3SPTSVC01.techsemi.com.sg', 'WAS3SPTSVC02.techsemi.com.sg', 'WAS3SPTSVC03.techsemi.com.sg'],
       # if subject based addressing is desired the address below could be specified instead of the server list above
#       'TECH_SINGAPORE' => ['/TECH_SINGAPORE/TECH/MFG/PROBE/PROD/PRODUCTTRACKSRV/COMMAND/BALANCED'],
       'LEHI'           => ['SVCLEMESPOOL01', 'SVCLEMESPOOL02', 'SVCLEMESPOOL03', 'SVCLEMESPOOL04', 'SVCLEMESPOOL05','SVCLEMESPOOL06'],
       'IMFS'           => ['SVCFSPRB1', 'SVCFSPRB2', 'SVCFSPRB3'],
       #'TAICHUNG'       => ['/TAICHUNG/MMT/MFG/PROBE/PROD/PRODUCTTRACKSRV/COMMAND'],
       #'TAICHUNG'       => ['/TAICHUNG/MMT/MFG/PROBE/BETA/PRODUCTTRACKSRV/COMMAND'],
       'TAOYUAN'        => ['/TAOYUAN/MTTW/MFG/PROBE/PROD/PRODUCTTRACKSRV/COMMAND/BALANCED'],
       'HIROSHIMA'      => ['/HIROSHIMA/MMJ/MFG/PROBE/PROD/PRODUCTTRACKSRV/COMMAND/BALANCED'],
       'TAICHUNG'       => ['/TAICHUNG/MMT/MFG/PROBE/PROD/DATAEXTSRV/MESSAGES'],
    },
    'PCT_ADMIN_MAIL' => {
       'BOISE'          => ['PROBE_TEST_CENTRAL_SOFTWARE@micron.com'],
       'BOISE_3'        => ['PROBE_TEST_CENTRAL_SOFTWARE@micron.com'],
       'AVEZZANO'       => ['PROBE_TEST_CENTRAL_SOFTWARE@micron.com', 'MITPRBISTEAM@micron.com', 'MIT_IT_SUPPORT_CENTER@micron.com', 'rporzio@micron.com'],
       'MANASSAS'       => ['MTV_PRBSW_MONITOR@micron.com'],
       'NISHIWAKI'      => ['PROBE_TEST_CENTRAL_SOFTWARE@micron.com', 'maotaka@micron.com', 'nakao@micron.com', 'sichimaru@micron.com', 'tsaito@micron.com'],
       'TECH_SINGAPORE' => ['PROBE_TEST_CENTRAL_SOFTWARE@micron.com', 'TECH_IS_MES@micron.com', 'TECH_PRB_AUTOMATION@micron.com'],
       'LEHI'           => ['PROBE_TEST_CENTRAL_SOFTWARE@micron.com', 'F2_PRB_ENG_SW_ENGINEERS@micron.com'],
       'IMFS'           => ['PROBE_TEST_CENTRAL_SOFTWARE@micron.com', 'F10_PRB_ENG_SW_ENGINEERS@micron.com'],
       'TAOYUAN'        => ['PROBE_TEST_CENTRAL_SOFTWARE@micron.com'],
       'HIROSHIMA'      => ['PROBE_TEST_CENTRAL_SOFTWARE@micron.com'],
       'TAICHUNG'       => ['PROBE_TEST_CENTRAL_SOFTWARE@micron.com'],
    },
    # opt-in if desired
    'PCT_ADMIN_PAGE' => {
       'BOISE'          => [],
       'BOISE_3'        => [],
       'AVEZZANO'       => [],
       'MANASSAS'       => ['MTV_PRBSW_ONCALL'],
       'NISHIWAKI'      => [],
       'TECH_SINGAPORE' => [],
       'LEHI'           => [],
       'IMFS'           => [],
       'TAOYUAN'        => [],
       'HIROSHIMA'      => [],
       'TAICHUNG'       => [],
    },
    'ALLOW_HOLD_MTGROUPS' => {
       'BOISE'          => ['MTI_PRB_DEBUG_OVERRIDE'],
       'BOISE_3'        => ['MTI_PRB_DEBUG_OVERRIDE'],
       'AVEZZANO'       => [],
       'MANASSAS'       => [],
       'NISHIWAKI'      => [],
       'TECH_SINGAPORE' => [],
       'LEHI'           => [],
       'IMFS'           => [],
       'TAOYUAN'        => [],
       'HIROSHIMA'      => [],
       'TAICHUNG'       => [],
    },
);

# Temporary fix for TCP in TAICHUNG that should be made permanent after the transition completes...kbremkes
if ($ENV{'SITE_NAME'} =~ /TAICHUNG/i) {
    my $host = uc hostname();
    if ($host =~ /\w\w\w\wLJ\w\w\w\w/) {  # Ex: F01MLJC1D0
       $SITE_CFG{'Facility'}{'TAICHUNG'} = 'TCP';
       $SITE_CFG{'GeRMFacility'}{'TAICHUNG'} = 'TCP';
    }
}

# there is a bug in the input parameter pass-thru when you route through MESSRV
# the message must be changed if you go directly to the GeRM server
# there is also a Probe specific instance of the GeRM server, which is not ideal
# the FAB production server is MTI/MFG/RECIPEMGMT/PROD/SERVER/RECIPERESOLVER
# notice PROD vs PROBE

# this block is used if you want to hit GeRM server directly
#my $GERMSRV = 'MTI/MFG/RECIPEMGMT/PROBE/SERVER/RECIPERESOLVER';
#my $GERM_PARAM_NAME_KEYWORD = 'input_param_name';
#my $GERM_PARAM_NAME_EXTENSION = '';
#my $GERM_PARAM_VALUE_KEYWORD = 'input_param_value';
#my $GERM_PARAM_VALUE_EXTENSION = '';

# this block is used if you route through MESSRV
my $GERMSRV = 'MTI/MFG/MESSRV/PROD/SERVER/MESSRV';
my $GERM_PARAM_NAME_KEYWORD = 'input_param';
my $GERM_PARAM_NAME_EXTENSION = '.name';
my $GERM_PARAM_VALUE_KEYWORD = 'input_param';
my $GERM_PARAM_VALUE_EXTENSION = '.value';

# this is used for DEBUG Output
local *DEBUG_FILE;

Tk::CmdLine::SetArguments;

# read command line options
GetOptions(
    \%OPT,
    'debug:s',       # displays debug information, no value indicates STDOUT or file name can be specified
    'ALLOW_HOLD',    # skip on Hold check - valid if testing offline or under some controlled conditions
    'NO_TRACK_CHECK',# skip Lot Tracking Check - only valid if testing offline
    'USE_PCT_CACHE', # use the cached PCT file instead of calling PCT_START_CARD - only valid if testing offline
    'carrier_fix',   # remove scrapped wafers from MES Carrier to avoid some carrier mismatch errors
    'dual',          # true indicates dual cassette (load port)
    'nostage',       # true prevents sending Run State Stage command
    'notemp',        # skip check for Temperature from GeRM
    'offline',       # for testing
    'b_left|bleft',  # controls placement for dual headed systems
    'trend',         # requested by MJP, not used in Boise
    'override:s',    # allow GeRM over-ride, no value indicates Engineering State or provide csv e10 states
    'backdoor',      # allow GeRM over-ride in any Equipment State [deprecated] see override
    'grid',          # experiment to use grid instead of pack
    'rfid',          # gets probe card id directly from PCT, relies on a RFID reader for every probe card in the tester
    'pid_sort',      # use alpha sort instead of order controlled by djlopez
    'custom',        # allow platform specific customization
    'cleanjob',      # uncompress a fresh test job copy every lot start
    'alter_batch_ok',# CAUTION! set lot state to Committed even if wafers are removed from the batch
    'partial_commit',# CAUTION! disables ISTRK02898745 - send Probe Process Commit for BSC_MODE or any Production Mode
    'no_batch_clean',# CAUTION! disables ISTRK02887576 - prevents aborting batches in a Running state
    'bsc',           # obtain information from batch stage controller
    'bsc_bypass:s',  # allow lots to be introduced with BSC over-ride, no value is any state or provide csv e10 states
    'auto_confirm',  # automatically update jobs, move tables, etc.
    'auto_override', # can be used to pre-select the override check-box, may be useful for programmatic override
    'mtcard_info',   # for backward compatibility - overtravel, planarity, card soak from Move Table
    'independent',   # if specified each load port setup is independent of all other load ports (Laser and Scrubber)
    'stage_to_mf',   # allows lots to be staged to mainframe instead of process chamber or load port
    'job_movetable', # use the move table inside the job folder if available - used by TECH Singapore [deprecated]
    'skip_recovery', # interrupt recovery logic is bypassed - wafers may be probed unnecessarily
    'pkg_test',      # tracking system is MAM
    'site=s',        # this can be used instead of ENV{'SITE_NAME'}
    'pid_germ',      # obtain Data Collection Process ID from GeRM
    'notk',          # suppress Graphical Window, display errors to stderr
    'encode=s',      # specify character encoding (for older OS and Tk)
    'group_name=s',  # ProcessGroupName process ID filter - FUNCT, CLEAN, PARAM, LASER, BAKE
    'brand=s',       # image file or message to display
    # these options are mostly for testing
    'equip_id=s',    # specify a tester
    'cardA|cardS=s', # allow A Prober Card ID to be specified
    'cardB=s',       # allow B (if app.) Prober Card ID to be specified
    'cardC=s',       # allow C (if app.) Prober Card ID to be specified
    'frontA|lotA=s', # allow A primary load port LotID to be specified
    'frontB|lotB=s', # allow B (if app.) primary load port LotID to be specified
    'frontC|lotC=s', # allow C (if app.) primary load port LotID to be specified
    'rearA=s',       # allow A secondary load port LotID to be specified
    'rearB=s',       # allow B (if app.) secondary load port LotID to be specified
    'rearC=s',       # allow C (if app.) secondary load port LotID to be specified
    'oper=s',        # for specifying Operator ID
    'home=s',        # application root dir for logging, temp files, ...
    'move_table=s',  # requested by TECH - only valid in override mode or when not specified by GeRM
    'reason=s',      # reason for over-riding setup - pre-populates Override Reason
    'job=s',         # only valid in override mode - pre-populates Override Job Name
    'pid=s',         # only valid in override mode - pre-populates Data Collection Process ID
    'temp=i',        # only valid in override mode if Temperature is specified in 'RequiredParams'
    'carrier=s',     # set to view or edit or csv e10 states to enable edit
    'process_run=s', # csv e10 states that allow a selected GeRM process to be started
    'process_type=s',# GeRM process Type that can be selected by user for process_run
    'mode_select=s', # csv e10 states that allow Data Collection Mode to be changed
    'config=s',      # for specifying the platform specific Perl configuration file
    'relation=s',    # specify [Load]port or [Process]chamber to only show that child relation
    'skip_instr_display', # Don't wait for operator instructions to be displayed
    'bypass_sr3_reqs',    # SR3 requirements of reprobes and testjob rev verifications skipped -- this violates those CQs - expected to be temporary
    'device_file=s', # only valid in override mode - pre-populates germ_device_file
    'design_id=s',   # only valid in override mode - pre-populates design_id
);

# read Localized messages
if (-r $MESSAGE_PATH) {
    require $MESSAGE_PATH;
} else {
    my $local_message_path = File::Spec->catfile($BASEDIR, $MESSAGE_FILE);
    if (-r $local_message_path) {
        require $local_message_path;
    } else {
        fatal_startup_error("Can't find $MESSAGE_FILE");
    }
}
# site is required
if ($OPT{'site'}) {
    $OPT{'site'} = uc $OPT{'site'};
} elsif ($ENV{'SITE_NAME'}) {
    $OPT{'site'} = $ENV{'SITE_NAME'};
} else {
    fatal_startup_error("ENV{'SITE_NAME'} or -site=<site_name> required");
}
if (!$SITE_CFG{'Facility'}{$OPT{'site'}}) {
    fatal_startup_error("Unrecognized Site '$OPT{'site'}'");
}
# read configuration file
read_platform_config_file();
# initialize resources
if (-r $RESOURCE_PATH) {
    Tk::CmdLine::LoadResources(
        -file => $RESOURCE_PATH,
        -priority => 'userDefault', # 'startupFile' is too low of priority to work with my settings
    );
} else {
    my $local_resource_path = File::Spec->catfile($BASEDIR, $RESOURCE_FILE);
    if (-r $local_resource_path) {
        Tk::CmdLine::LoadResources(
            -file => $local_resource_path,
            -priority => 'userDefault',
        );
    }
}

initialize_variables();
get_equip_info();
get_offline_variables();
$CURRENT_STATE = check_current_equipment_state();

# set operator required if in an engineering state and configured for allow hold mtgroups 
if(scalar @{$SITE_CFG{'ALLOW_HOLD_MTGROUPS'}{$OPT{'site'}}}){
   foreach my $prober (keys %{$ET_STATE{$TESTER_ID}{'child'}}) {
       if ($ET_STATE{$TESTER_ID}{'child'}{$prober}{'state'} eq "ENGINEERING") {
           $NO_OPERATOR_REQUIRED = 0;  # To facilitate the ALLOW_HOLDS by user feature in Engineering.
       }
   } 
}

initialize_platform_variables();
build_main_window();
build_oper_entry('top_frame');
build_lot_entry('child_frame');
build_process_entry('top_frame');
build_lot_info('child_frame');
build_confirm_settings('top_frame');
build_job_info('top_frame');
build_override_entry('top_frame');
get_probe_process_IDs() unless $OPT{'pkg_test'};
page_to('oper_entry');
if ($OPT{'custom'}) {
    PrbCfg::custom_menu();
} else {
    check_for_minimum_data();
    MainLoop;
}

###############################################################################
# Description:
#     load the platform config file that is used to customize the
#     lot introduction menu for a particular tester or tester platform
# Returns:
#     nothing
# Globals:
#     $CONFIG_PATH, $TESTER_ID, %OPT
###############################################################################
sub read_platform_config_file {
    my $host = uc hostname();
    $host =~ s/\..*$//;  # strip extension if applicable (i.e. v01m11vizx.micron.com)
    if ($OPT{'equip_id'}) {
        $TESTER_ID = uc $OPT{'equip_id'};
    } else {
        $TESTER_ID = $host;
    }
    if ($TESTER_ID ne $host) {
        $OPT{'offline'} = 1;
    }
    if ($OPT{'config'} and -r $OPT{'config'}) {
        require $OPT{'config'};
    } elsif (-r $CONFIG_PATH) {
        require $CONFIG_PATH;
    } else {
        my $local_config_path = File::Spec->catfile($BASEDIR, $CONFIG_FILE);
        if (-r $local_config_path) {
            require $local_config_path;
        } else {
            fatal_startup_error("Can't find $CONFIG_FILE");
        }
    }
}

###############################################################################
# Description:
#     initializes several global variables to make it easier to work in the
#     Tk Event Loop
# Returns:
#     nothing
# Globals:
#     $TESTER_ID, $FRONT_CASSETTE_LABEL, $PROBER_PACK_ORDER, $LOG_DIR,
#     $LOG_FILE, $CACHE_DIR, %OPT, %ENV
###############################################################################
sub initialize_variables {
    if (defined $OPT{'debug'}) {
        $DEBUG_MODE = 1;
        unlink $OPT{'debug'} if (-f $OPT{'debug'});
        if (!$OPT{'debug'} or !open(DEBUG_FILE, ">$OPT{'debug'}")) {
            *DEBUG_FILE = *STDOUT;
        }
        $MESInterface::DEBUG = *DEBUG_FILE;
    } else {
        $DEBUG_MODE = 0;
    }
    if ($OPT{'encode'}) {
        if ($OPT{'encode'} !~ /none/i) {
            $ENCODING = $OPT{'encode'};
        }
    } elsif ($^O =~ /solaris/i) {
        $ENCODING = 'iso-8859-1';
    }
    if ($OPT{'dual'}) {
        $FRONT_CASSETTE_LABEL = $PrbLocale::Msg{'front_loader'};
    } else {
        $FRONT_CASSETTE_LABEL = $PrbLocale::Msg{'single_loader'};
    }
    # controls placement of Probers in dual headed configuration
    $PROBER_PACK_ORDER = 'right' if ($OPT{'b_left'});
    # this will probably change, but this will setup resource options that
    # can be displayed in the carrier map
    # I am flipping all the keys and values, this may change
    foreach my $internal_value (keys %PrbLocale::SlotSelectionOptions) {
        # this may also change (it will probably be platform configurable)
        # for now keep the user options restricted to a limited subset
        if ($internal_value =~ /(DataComplete)|(Committed)|(Processed)|(DataAborted)/) {
            $SLOT_ASSIGNMENTS{$PrbLocale::SlotSelectionOptions{$internal_value}} = $internal_value;
        }
    }
    $LOG_DIR = $PrbCfg::PlatformCfg{'LogDir'};
    $LOG_FILE = File::Spec->catfile($LOG_DIR, uc($SCRIPT_FILE) . '.log');
    $WARN_FILE = File::Spec->catfile($LOG_DIR, uc($SCRIPT_FILE) . '.warn');
    $CACHE_DIR = $PrbCfg::PlatformCfg{'CacheDir'};
    my $existing_umask = umask(0000);
    if (!-d $LOG_DIR and !(mkdir $LOG_DIR, 0777)) {
        fatal_startup_error(PrbLocale::mkdir_fail($LOG_DIR, $!));
    }
    if (!-d $CACHE_DIR and !(mkdir $CACHE_DIR, 0777)) {
        fatal_startup_error(PrbLocale::mkdir_fail($CACHE_DIR, $!));
    }
    umask($existing_umask);
    if ($OPT{'pkg_test'}) {
        $MESSRV .= '/BACKEND';
        return;
    }
    # allow a site to use subject based addressing to talk to ProbeTracking instead of Peer-to-Peer
    my $peer_to_peer_detected = 0;
    foreach my $server (@{$SITE_CFG{'PrbTrack'}{$OPT{'site'}}}) {
        if ( $server !~ /\// ) {
            $peer_to_peer_detected = 1;
        }
    }
    if ( !$peer_to_peer_detected ) {
        $ProbeTrackInterface::TRACKING_SERVER_PORT = 0;  # use subject based addressing instead of Peer-Peer
    }
    if ($OPT{'USE_PCT_CACHE'} and !$OPT{'offline'}) {
        $OPT{'USE_PCT_CACHE'} = (); # this option is only valid when testing offline
    }
}

###############################################################################
# Description:
#     initializes several global variables to make it easier to work in the
#     Tk Event Loop
# Returns:
#     nothing
# Globals:
#     $JOB_RELEASE_SERVER, $MOVE_TABLE_SERVER, $LOCAL_JOB_DIR, $JOB_META_DIR,
#     $LOCAL_MOVE_TABLE_DIR, $MAX_JOB_AGE_DAYS,
#     $LOCAL_JOB_ARCHIVE_DIR
###############################################################################
sub initialize_platform_variables {
    $JOB_RELEASE_SERVER = $PrbCfg::PlatformCfg{'RelSrv'};
    $MOVE_TABLE_SERVER = $PrbCfg::PlatformCfg{'StepTableSrv'};
    $LOCAL_JOB_DIR = $PrbCfg::PlatformCfg{'JobDir'} if $PrbCfg::PlatformCfg{'JobDir'};
    $JOB_META_DIR = $PrbCfg::PlatformCfg{'JobMeta'} if $PrbCfg::PlatformCfg{'JobMeta'};
    $LOCAL_JOB_ARCHIVE_DIR = $PrbCfg::PlatformCfg{'ArchiveDir'} if $PrbCfg::PlatformCfg{'ArchiveDir'};
    # fallback to JobMeta directory as the Archive Directory if ArchiveDir is not defined
    $LOCAL_JOB_ARCHIVE_DIR = $PrbCfg::PlatformCfg{'JobMeta'} if ($PrbCfg::PlatformCfg{'JobMeta'} and !defined $PrbCfg::PlatformCfg{'ArchiveDir'});
    $LOCAL_MOVE_TABLE_DIR = $PrbCfg::PlatformCfg{'MoveTableDir'} if $PrbCfg::PlatformCfg{'MoveTableDir'};
    $MAX_JOB_AGE_DAYS = $PrbCfg::PlatformCfg{'MaxTestJobAge'};
    if ($OPT{'bsc'} and defined $OPT{'bsc_bypass'} and !$OPT{'bsc_bypass'}) {
        # -bsc_bypass specified with no value, allow all SEMI-E10 States - this keeps the related logic simpler
        $OPT{'bsc_bypass'} = 'NON-SCHEDULED,UNSCHEDULED_DOWNTIME,SCHEDULED_DOWNTIME,ENGINEERING,STANDBY,PRODUCTIVE';
    }
    if ($OPT{'backdoor'}) {
        # I would like to deprecate this option, for now treat it as a shortcut for override in any state
        $OPT{'override'} = 'NON-SCHEDULED,UNSCHEDULED_DOWNTIME,SCHEDULED_DOWNTIME,ENGINEERING,STANDBY,PRODUCTIVE';
    } elsif (defined $OPT{'override'} and !$OPT{'override'}) {
        # traditionally specifying -override with no value meant allow only in Engineering State
        $OPT{'override'} = 'ENGINEERING';
    }
    if ($OPT{'carrier'} and ($OPT{'carrier'} =~ /edit/i)) {
        # edit is a special keyword that allows all SEMI-E10 States to edit carrier
        $OPT{'carrier'} = 'NON-SCHEDULED,UNSCHEDULED_DOWNTIME,SCHEDULED_DOWNTIME,ENGINEERING,STANDBY,PRODUCTIVE';
    }
    if ($OPT{'override'} and !$OPT{'carrier'}) {
        # user is required to acknowledge wafers to probe by viewing (or editing) carrier map
        # the carrier must be viewable (at a minimum)
        $OPT{'carrier'} = 'view';
    }
    refresh_setup_options();
    # for equipment with no probecard, set -cardA=none
    if ($OPT{'cardA'} and ($OPT{'cardA'} =~ m/^no/i)) {
        $NO_PROBECARD = 1;
    }
    $OPT{'group_name'} = 'FUNCT_MENU' unless $OPT{'group_name'};  # can be changed via options if needed
    my $existing_umask = umask(0000);
    if (!-d $LOCAL_JOB_ARCHIVE_DIR and !(mkdir $LOCAL_JOB_ARCHIVE_DIR, 0777)) {
        fatal_startup_error(PrbLocale::mkdir_fail($LOCAL_JOB_ARCHIVE_DIR, $!));
    }
    if (!-d $JOB_META_DIR and !(mkdir $JOB_META_DIR, 0777)) {
        fatal_startup_error(PrbLocale::mkdir_fail($JOB_META_DIR, $!));
    }
    if (!-d $PrbCfg::PlatformCfg{'HeaderDir'} and !(mkdir $PrbCfg::PlatformCfg{'HeaderDir'}, 0777)) {
        fatal_startup_error(PrbLocale::mkdir_fail($PrbCfg::PlatformCfg{'HeaderDir'}, $!));
    }
    if (!-d $PrbCfg::PlatformCfg{'AttrDir'} and !(mkdir $PrbCfg::PlatformCfg{'AttrDir'}, 0777)) {
        fatal_startup_error(PrbLocale::mkdir_fail($PrbCfg::PlatformCfg{'AttrDir'}, $!));
    }
    umask($existing_umask);
}

###############################################################################
# Description:
#     initializes global variables with command line arguments (for testing)
# Returns:
#     nothing
# Globals:
#     $OPERATOR_ID, $OPERATOR_NAME, $EMPLOYEE_NAME, %OPT, %PCARD_ID, %LOAD_PORT
###############################################################################
sub get_offline_variables {
    # for testing it is desirable to have some information provided on command line
    if ($OPT{'oper'} and ($OPT{'oper'} =~ m/^no/i)) {
        # other automation software may be relying on a numeric operator ID
        $OPERATOR_ID = 0;
        $NO_OPERATOR_REQUIRED = 1;  # to supress data entry fields
        $EMPLOYEE_NAME = 'unknown';
        $OPERATOR_NAME = PrbLocale::format_name('AUTOMATION', 'USER');
    } elsif ($OPT{'oper'}) {
        $OPERATOR_ID = $OPT{'oper'};
    }
    foreach my $prober (sort keys %LOAD_PORT) {
        my $prober_alias = uc prober_alpha_designator($prober);
        if ($OPT{"card${prober_alias}"}) {
            $PCARD_ID{$prober} = $OPT{"card${prober_alias}"};
        } elsif ($OPT{'offline'}) {
            # for offline testing use the card that is saved in ET for this equipment
            $PCARD_ID{$prober} = $ET_ITEMS{$TESTER_ID}{'child'}{$prober}{'PRB_CARD'}{'value'};
        }
        if ($OPT{"front${prober_alias}"}) {
            $LOAD_PORT{$prober}{'front'}{'lot_id'} = $OPT{"front${prober_alias}"};
        }
        if ($OPT{"rear${prober_alias}"}) {
            $LOAD_PORT{$prober}{'rear'}{'lot_id'} = $OPT{"rear${prober_alias}"};
        }
    }
}

###############################################################################
# Description:
#     calls platform specific function to check if lots are currently probing
# Returns:
#     'idle' or 'probing'
# Globals:
#     %LOAD_PORT
###############################################################################
sub check_current_equipment_state {
    time_it('check_current_state');
    my $status = PrbCfg::check_current_state();
    time_it('check_current_state', 'end');
    if ($status) {
        fatal_startup_error(PrbLocale::error_checking_equip_state($status));
    }
    foreach my $prober (keys %LOAD_PORT) {
        foreach my $cassette (keys %{$LOAD_PORT{$prober}}) {
            if ($LOAD_PORT{$prober}{$cassette}{'status'} eq 'active') {
                return('probing');
            }
        }
    }
    return('idle');
}

###############################################################################
# Description:
#     create main Tk window
# Returns:
#     nothing
# Globals:
#     %W, %OPT
###############################################################################
sub build_main_window {
    my $resource_class = 'Menu';
    if ($OPT{'ALLOW_HOLD'}) {
        $resource_class = 'Caution';
    }
    elsif ($OPT{'offline'}) {
        $resource_class = 'Offline';
    }
    $W{'main'} = new MainWindow(
        -class => $resource_class,
        -title => $PrbLocale::Msg{'title'},
    );
    $W{'main'}->withdraw() if $OPT{'notk'};
    $W{'top_frame'} = $W{'main'}->Frame()->pack(
        -fill => 'x',
    );
    $W{'child_frame'} = $W{'main'}->Frame()->pack(
        -fill   => 'x',
    );
    # Operator Message Window:
    $W{'status'} = $W{'main'}->Scrolled('ROText',
        -height => 4,
        -scrollbars => 'osoe',
        -wrap => 'word',
        -takefocus => 0,  # improves tab order navigation
    )->pack(
        -fill => 'x',
    );
    $W{'default_fg'} = $W{'status'}->cget(-foreground);
    $W{'default_bg'} = $W{'status'}->cget(-background);
    # Navigation Buttons:
    my $navig_frame = $W{'main'}->Frame()->pack();
    # Previous:
    $W{'previous'} = $navig_frame->Button(
        'Name' => 'PreviousButton',
        -text  => $PrbLocale::Msg{'previous'},
    )->pack(
        -side => 'left',
        -padx => 10,
        -pady => 10,
    );
    # Next:
    $W{'next'} = $navig_frame->Button(
        'Name' => 'NextButton',
        -textvariable => \$NEXT_SCREEN_LABEL,
    )->pack(
        -side => 'left',
        -padx => 10,
        -pady => 10,
    );
    # Cancel:
    $navig_frame->Button(
        'Name' => 'CancelButton',
        -text => $PrbLocale::Msg{'cancel'},
        -command => sub {&tk_cancel();},
    )->pack(
        -side => 'left',
        -padx => 10,
        -pady => 10,
    );
}

###############################################################################
# Description:
#     display main Tk window
# Returns:
#     nothing
# Globals:
#     %W
###############################################################################
sub show_main_window {
    if (Exists($W{'main'})) {
        $W{'main'}->deiconify();
        $W{'main'}->raise();
    }
}

###############################################################################
# Description:
#     create Tk frame used to enter operator ID
# Returns:
#     nothing
# Globals:
#     $OPERATOR_ID, $OVERRIDE, %EQUIP_STATE_ALLOW, %W
###############################################################################
sub build_oper_entry {
    my ($parent) = @_;
    $W{'oper_entry'} = $W{$parent}->Frame();
    unless ($NO_OPERATOR_REQUIRED) {
        my %pack_options = (
            -side => 'left',
            -padx => 10,
            -pady => 10,
        );
        build_employee_entry('oper_entry', 1, %pack_options);
    }
    # this is almost duplicated in build_process_entry
    # this allows the Deviation drop down to be displayed on the first
    # page, when pid_germ is specified (skipping process_entry page)
    if ($OPT{'pid_germ'}) {
        # see build_process_entry
        my %pack_options = (
            -side => 'left',
            -padx   => 10,
        );
        build_deviation_entry('oper_entry', 'normal', %pack_options);
    }
    # Override Batch Stage Controller option
    if ($OPT{'bsc_bypass'}) {
        my $button_state = $EQUIP_STATE_ALLOW{'bsc_bypass'} ? 'normal' : 'disabled';
        $W{'bsc_bypass'} = $W{'oper_entry'}->Checkbutton(
            -text     => $PrbLocale::Msg{'ignore_bsc'},
            -variable => \$OVERRIDE{'bsc_bypass'},
            -state    => $button_state,
            -takefocus => 0,  # improves tab order navigation
        )->pack(
            -side   => 'left',
            -padx   => 10,
            -pady => 10,
        );
    }
    # Override option
    if ($OPT{'override'}) {
        my $button_state = $EQUIP_STATE_ALLOW{'override'} ? 'normal' : 'disabled';
        if ($EQUIP_STATE_ALLOW{'override'} and $OPT{'auto_override'}) {
            $OVERRIDE{'requested'} = 1;
            tk_override_button_callback();
        }
        $W{'oper_entry'}->Checkbutton(
            -text     => $PrbLocale::Msg{'override'},
            -variable => \$OVERRIDE{'requested'},
            -state    => $button_state,
            -command  => [\&tk_override_button_callback],
            -takefocus => 0,  # improves tab order navigation
        )->pack(
            -side   => 'left',
            -padx   => 10,
            -pady => 10,
        );
    }
    if ($OPT{'brand'}) {
        if (-e $OPT{'brand'}) {
            eval {
                my ($image_basename, $image_subpath, $image_ext) = fileparse($OPT{'brand'}, qr/\..*/);
                if ($image_ext =~ /png/i) {
                    require Tk::PNG;
                }
                my $image = $W{'main'}->Photo(-file => $OPT{'brand'});
                $W{'oper_entry'}->Label(
                    -image => $image,
                    -takefocus => 0,
                    -padx => 5,
                    -pady => 5,
                )->pack(
                    -side => 'left',
                    -padx => 20,
                    -pady => 10,
                );
            };
        } else {
            $W{'oper_entry'}->Label(
                -text => $OPT{'brand'},
                -takefocus => 0,
                -padx => 5,
                -pady => 5,
            )->pack(
                -side => 'left',
                -padx => 20,
                -pady => 10,
            );
        }
    }
}

###############################################################################
# Description:
#     create Tk frame used to select Process Step, and Engineering Deviation
#     this operator screen has 2 primary purposes
#     1) allow user to change the Process Mode (-mode_select)
#     2) select the PID, and Engineering Deviation for call to tk_get_recipe
# Returns:
#     nothing
# Globals:
#     $OPERATOR_NAME, $DESIGN_ID, $STEP_NAME, ENGR_REQUEST, %PROCESS, %W
###############################################################################
sub build_process_entry {
    my ($parent) = @_;
    $W{'process_entry'} = $W{$parent}->Frame();
    unless ($NO_OPERATOR_REQUIRED) {
        # Operator:
        my $oper_frame = $W{'process_entry'}->Frame()->pack(
            -fill => 'x',
        );
        $oper_frame->Label(
            -text  => $PrbLocale::Msg{'operator_name'},
        )->pack(
            -side   => 'left',
            -anchor => 'e',
            -padx   => 10,
        );
        $oper_frame->Label(
            -textvariable => \$OPERATOR_NAME,
        )->pack(
            -side   => 'right',
            -anchor => 'w',
            -padx   => 10,
            -fill => 'x',
        );
    }
    # Design:
    my $design_frame = $W{'process_entry'}->Frame()->pack(
        -fill => 'x',
    );
    $design_frame->Label(
        -text  => $PrbLocale::Msg{'design'},
    )->pack(
        -side   => 'left',
        -anchor => 'e',
        -padx   => 10,
    );
    $design_frame->Label(
        -textvariable => \$DESIGN_ID,
    )->pack(
        -side   => 'right',
        -anchor => 'w',
        -padx   => 10,
        -fill => 'x',
    );
    # Step:
    my $step_frame = $W{'process_entry'}->Frame()->pack(
        -fill => 'x',
    );
    $step_frame->Label(
        -text  => $PrbLocale::Msg{'step'},
    )->pack(
        -side   => 'left',
        -anchor => 'e',
        -padx   => 10,
    );
    $step_frame->Label(
        -textvariable => \$STEP_NAME,
    )->pack(
        -side   => 'right',
        -anchor => 'w',
        -padx   => 10,
        -fill => 'x',
    );
    # Process ID:
    my $pid_frame = $W{'process_entry'}->Frame()->pack(
        -fill => 'x',
    );
    $pid_frame->Label(
        -text  => $PrbLocale::Msg{'process_id'},
    )->pack(
        -side   => 'left',
        -anchor => 'e',
        -padx   => 10,
    );
    $W{'pid_list'} = $pid_frame->BrowseEntry(
        -textvariable => \$PROCESS{'selected'},
        -state        => 'readonly',             # user can't change the list items
        -browsecmd    => [ \&tk_pid_selected, ],
        -width        => 40,
        -buttontakefocus => 0,
    )->pack(
        -side   => 'right',
        -anchor => 'w',
        -padx   => 10,
        -fill => 'x',
    );
    if (!$OPT{'pid_germ'}) {
        # see build_override_entry
        my %pack_options = (
            -side   => 'right',
            -anchor => 'w',
            -padx   => 10,
            -fill => 'x',
        );
        build_deviation_entry('process_entry', 'disabled', %pack_options);
    }
}

###############################################################################
# Description:
#     create Tk frame and BrowseEntry used to select Engineering Deviation
# Returns:
#     nothing
# Globals:
#     $ENGR_REQUEST, %OPT, %W
###############################################################################
sub build_deviation_entry {
    my ($parent, $initial_state, %pack_options) = @_;
    my @engr_request_options;
    my $deviation_label = $PrbLocale::Msg{'deviation_type'};
    if ($OPT{'process_type'} and $EQUIP_STATE_ALLOW{'process_run'}) {
        $deviation_label = PrbLocale::process_type_label($OPT{'process_type'});
        my $process_list_status;
        ($process_list_status, @engr_request_options) = get_process_list($OPT{'process_type'});
        if ($process_list_status) {
            fatal_startup_error(PrbLocale::germ_process_list_error($OPT{'process_type'}, $process_list_status));
        } elsif (scalar @engr_request_options) {
            # limit the BrowseEntry to only the options returned from get_process_list
            $initial_state = 'readonly';
        }
    } else {
        foreach my $option (sort keys %PrbLocale::EngrRequest) {
            push @engr_request_options, $option;
        }
    }
    if (scalar @engr_request_options) {
        # Deviation:
        my $deviation_frame = $W{$parent}->Frame()->pack(
            -fill => 'x',
        );
        $deviation_frame->Label(
            -text  => $deviation_label,
        )->pack(
            -side   => 'left',
            -anchor => 'e',
            -padx   => 10,
        );
        $W{'request_list'} = $deviation_frame->BrowseEntry(
            -textvariable => \$ENGR_REQUEST,
            -state        => $initial_state,
            -width        => 40,
            -buttontakefocus => 0,
        )->pack(%pack_options);
        tk_configure_options('request_list', @engr_request_options);
        # user can enter a custom deviation
        $W{'request_list'}->bind('<Return>', [\&tk_add_option, 'request_list', \$ENGR_REQUEST]);
    }
}

###############################################################################
# Description:
#     create Tk frame and Entry used to enter employee ID
# Returns:
#     nothing
# Globals:
#     $ENGR_REQUEST, %OPT, %W
###############################################################################
sub build_employee_entry {
    my ($parent, $take_focus, %pack_options) = @_;
    # Operator Number:
    my $oper_frame = $W{$parent}->Frame()->pack(
        -fill => 'x',
    );
    $oper_frame->Label(
        -text  => $PrbLocale::Msg{'operator_number'},
    )->pack(
        -side => 'left',
        -padx => 10,
        -pady => 10,
    );
    my $operator_id_entry = $oper_frame->Entry(
        -textvariable => \$OPERATOR_ID,
        -validate        => 'key',
        -validatecommand => [ \&tk_validate_numeric ],
    )->pack(%pack_options);
    fix_keypad($operator_id_entry);
    # the operator entry widget may get keyboard focus
    $operator_id_entry->focus if $take_focus;
}

###############################################################################
# Description:
#     create Tk frame used to enter LotIDs
# Returns:
#     nothing
# Globals:
#     $PROBER_PACK_ORDER, $FRONT_CASSETTE_LABEL, %LOAD_PORT, %OPT, %ET_STATE,
#     %W
###############################################################################
sub build_lot_entry {
    my ($parent) = @_;
    $W{'lot_entry'} = $W{$parent}->Frame();
    my $col;
    my $initial_focus_defined = $NO_OPERATOR_REQUIRED ? 0 : 1;
    # clunky - in development
    if ($PROBER_PACK_ORDER eq 'left') {
        $col = scalar keys %LOAD_PORT;
    } else {
        $col = 1;
    }
    foreach my $prober (sort keys %LOAD_PORT) {
        my $probe_frame = $W{'lot_entry'}->LabFrame(
            -label => $prober,
            -labelside => 'acrosstop',
        );
        if ($OPT{'grid'}) {
            $probe_frame->grid(
                -column => $col,
                -row => 0,
            );
            if ($PROBER_PACK_ORDER eq 'left') {
                ++$col;
            } else {
                --$col;
            }
        } else {
            $probe_frame->pack(
                -fill   => 'both',
                -side => $PROBER_PACK_ORDER,
                -padx => 10,
                -pady => 10,
            );
        }
        # Equipment State:
        my $equipment_sub_state = $NO_CHILD_EQUIPMENT ? $ET_STATE{$TESTER_ID}{'sub_state'} : $ET_STATE{$TESTER_ID}{'child'}{$prober}{'sub_state'};
        my $equipment_state = $NO_CHILD_EQUIPMENT ? $ET_STATE{$TESTER_ID}{'state'} : $ET_STATE{$TESTER_ID}{'child'}{$prober}{'state'};
        my $state_frame = $probe_frame->Frame()->pack(
            -anchor => 'w',
            -fill   => 'x',
            -padx   => 10,
            -pady   => 10,
        );
        $state_frame->Label(
            -text  => $equipment_sub_state,
            -class => lc $equipment_state,
        )->pack(
            -side => 'left',
            -padx => 10,
        );
        # Copy Lot ID Button:
        if ((scalar keys %LOAD_PORT) > 1) {
            # relies on current naming convention, 4th character of prober should be A, B, or S
            # no need to worry about single headed systems
            if ((my $head_id) = lc($prober) =~ /^\w{3}([ab])/) {
                $state_frame->Button(
                    -text    => $PrbLocale::Msg{"copy_from_${head_id}"},
                    -command => [ \&copy_lot_info, $prober ],
                    -takefocus => 0,  # improves tab order navigation
                )->pack(
                    -side => 'right',
                    -padx => 10,
                );
            }
        }

        my $cassette_label;
        foreach my $cassette (reverse(sort keys %{$LOAD_PORT{$prober}})) {
            if ($cassette eq 'front') {
                $cassette_label = $FRONT_CASSETTE_LABEL;
            } else {
                $cassette_label = $PrbLocale::Msg{'rear_loader'};
            }
            my $cassette_frame = $probe_frame->LabFrame(
                -label => $cassette_label,
                -labelside => 'acrosstop',
            )->pack(
                -fill => 'x',
                -padx => 10,
                -pady => 10,
            );
            my $lot_frame = $cassette_frame->Frame()->pack(
                -fill => 'x',
            );
            # Lot ID:
            $lot_frame->Label(
                -text => $PrbLocale::Msg{'lot_id'},
            )->pack(
                -side => 'left',
                -padx => 10,
                -pady => 10,
            );
            my $lot_entry = $lot_frame->Entry(
                -textvariable => \$LOAD_PORT{$prober}{$cassette}{'lot_id'},
            )->pack(
                -side => 'right',
                -padx => 10,
                -pady => 10,
            );
            if ($LOAD_PORT{$prober}{$cassette}{'status'} ne 'available') {
                $lot_entry->configure(
                    -state => 'disabled',
                    -background => $W{'default_bg'},
                    -foreground => $W{'default_fg'},
                );
            }
            fix_keypad($lot_entry);
            if (!$initial_focus_defined) {
                $lot_entry->focus;
                $initial_focus_defined = 1;
            }
        }
    }
}

###############################################################################
# Description:
#     create Tk frame used to display setup information
# Returns:
#     nothing
# Globals:
#     $PROBER_PACK_ORDER, $FRONT_CASSETTE_LABEL, %LOAD_PORT, %ET_STATE,
#     %PCARD_SUMMARY, %OPT, %W
###############################################################################
sub build_lot_info {
    my ($parent) = @_;

    $W{'lot_info'} = $W{$parent}->Frame();
    my $horizontal_padding = 10;
    my $vertical_padding = 5;

    my $col;
    # clunky - in development
    if ($PROBER_PACK_ORDER eq 'left') {
        $col = scalar keys %LOAD_PORT;
    } else {
        $col = 1;
    }
    foreach my $prober (sort keys %LOAD_PORT) {
        my $probe_frame = $W{'lot_info'}->LabFrame(
            -label => $prober,
            -labelside => 'acrosstop',
        );
        if ($OPT{'grid'}) {
            $probe_frame->grid(
                -column => $col,
                -row => 0,
            );
            if ($PROBER_PACK_ORDER eq 'left') {
                ++$col;
            } else {
                --$col;
            }
        } else {
            $probe_frame->pack(
                -fill   => 'x',
                -expand => 1,
                -side => $PROBER_PACK_ORDER,
                -padx => $horizontal_padding,
                -pady => $vertical_padding,
                );
        }
        # Equipment State:
        my $state_frame = $probe_frame->Frame()->pack(
            -anchor => 'w',
            -fill   => 'x',
            -padx   => $horizontal_padding,
            -pady   => $vertical_padding,
        );
        $state_frame->Label(
            -text  => $ET_STATE{$TESTER_ID}{'child'}{$prober}{'sub_state'},
            -class => lc $ET_STATE{$TESTER_ID}{'child'}{$prober}{'state'},
        )->pack(
            -side => 'left',
            -padx => $horizontal_padding,
        );
        # Probe Card:
        my $card_frame = $probe_frame->Frame()->pack(
            -anchor => 'w',
            -fill   => 'x',
            -padx   => $horizontal_padding,
        );
        $card_frame->Label(
            -textvariable  => \$PCARD_SUMMARY{$prober}{'id'},
        )->pack(
            -side => 'left',
            -padx => $horizontal_padding,
        );
        $card_frame->Label(
            -textvariable => \$PCARD_SUMMARY{$prober}{'description'},
        )->pack(
            -side => 'right',
            -padx => $horizontal_padding,
        );

        if ($OPT{'carrier'}) {
            $W{'carrier'} = $W{'main'}->SlotSelect(
                -title        => $PrbLocale::Msg{'carrier_title'},
                -label        => $PrbLocale::Msg{'wafer_select'},
                -lcount       => $PrbLocale::Msg{'carrier_count'},
                -lfirst       => $PrbLocale::Msg{'choose_first'},
                -llast        => $PrbLocale::Msg{'choose_last'},
                -lrandom      => $PrbLocale::Msg{'choose_random'},
                -lall         => $PrbLocale::Msg{'choose_all'},
                -lnone        => $PrbLocale::Msg{'choose_none'},
                -lok          => $PrbLocale::Msg{'ok'},
                -lcancel      => $PrbLocale::Msg{'cancel'},
                -slotoptions  => \%SLOT_ASSIGNMENTS,
                -empty        => $EMPTY_SLOT,
                -unassigned   => $UNASSIGNED_SLOT,
                -singlechoice => $PrbLocale::SlotSelectionOptions{'Committed'},
            );
            $W{'carrier'}->Hide();  # may be needed on Win32 to supress the toplevel until needed
            $W{'carrier'}->Subwidget('info')->configure(-foreground => $W{'default_fg'});
            $W{'carrier'}->Subwidget('status_bar')->configure(-foreground => $W{'default_fg'});
        }
        my $cassette_label;
        foreach my $cassette (reverse(sort keys %{$LOAD_PORT{$prober}})) {
            if ($cassette eq 'front') {
                $cassette_label = $FRONT_CASSETTE_LABEL;
            } else {
                $cassette_label = $PrbLocale::Msg{'rear_loader'};
            }
            my $cassette_frame = $probe_frame->LabFrame(
                -label => $cassette_label,
                -labelside => 'acrosstop',
            )->pack(
                -fill => 'x',
                -padx => $horizontal_padding,
                -pady => $vertical_padding,
            );
            # Lot ID:
            my $lot_frame = $cassette_frame->Frame()->pack(
                -fill => 'x',
            );
            $lot_frame->Label(
                -text => $PrbLocale::Msg{'lot_id'},
            )->pack(
                -side => 'left',
                -padx => $horizontal_padding,
            );
            $lot_frame->Label(
                -textvariable => \$LOAD_PORT{$prober}{$cassette}{'lot_id'},
            )->pack(
                -side => 'right',
                -padx => $horizontal_padding,
            );
            # Part Type:
            my $part_frame = $cassette_frame->Frame()->pack(
                -fill => 'x',
            );
            $part_frame->Label(
                -textvariable => \$LOAD_PORT{$prober}{$cassette}{'lot_type'},
            )->pack(
                -side => 'left',
                -padx => $horizontal_padding,
            );
            $part_frame->Label(
                -textvariable => \$LOAD_PORT{$prober}{$cassette}{'part_type'},
            )->pack(
                -side => 'right',
                -padx => $horizontal_padding,
            );
            # added to support Laser and scrubber
            if ($OPT{'independent'}) {
                foreach my $characteristic ('design', 'step', 'process_id', 'job_name') {
                    my $temp_frame = $cassette_frame->Frame()->pack(
                        -fill => 'x',
                    );
                    $temp_frame->Label(
                        -text => $PrbLocale::Msg{$characteristic},
                    )->pack(
                        -side => 'left',
                        -padx => $horizontal_padding,
                    );
                    $temp_frame->Label(
                        -textvariable => \$LOAD_PORT{$prober}{$cassette}{$characteristic},
                    )->pack(
                        -side => 'right',
                        -padx => $horizontal_padding,
                    );
                }
            }
            # Wafer Quantity:
            my $quantity_frame = $cassette_frame->Frame()->pack(
                -fill => 'x',
            );
            $quantity_frame->Label(
                -text => $PrbLocale::Msg{'wafer_count'},
            )->pack(
                -side => 'left',
                -padx => $horizontal_padding,
            );
            $quantity_frame->Label(
                -textvariable => \$LOAD_PORT{$prober}{$cassette}{'quantity'},
            )->pack(
                -side => 'right',
                -padx => $horizontal_padding,
            );
            if ($OPT{'trend'}) {
                # Trend Wafers:
                my $trend_frame = $cassette_frame->Frame()->pack(
                    -fill => 'x',
                );
                $trend_frame->Label(
                    -text => $PrbLocale::Msg{'trend_count'},
                )->pack(
                    -side => 'left',
                    -padx => $horizontal_padding,
                );
                $trend_frame->Entry(
                    -textvariable => \$LOAD_PORT{$prober}{$cassette}{'trend'},
                    -class        => 'shortint',
                    -justify => 'right',
                    -validate        => 'key',
                    -validatecommand => [ \&tk_validate_quantity, $prober, $cassette],
                )->pack(
                    -side    => 'right',
                    -padx    => $horizontal_padding,
                );
            }
            if ($OPT{'carrier'}) {
                # Carrier Map
                $W{"${prober}_${cassette}_map"} = $cassette_frame->Button(
                    -text => $PrbLocale::Msg{'display_carrier'},
                    -command => [ \&tk_display_carrier, $prober, $cassette ],
                    -state => 'disabled',
                )->pack(
                    -side => 'right',
                    -padx => $horizontal_padding,
                    -pady => $vertical_padding,
                );

            }
        }
    }
}

###############################################################################
# Description:
#     create Tk frame used to enter yes/no response to certain setup options
# Returns:
#     nothing
# Globals:
#     $LOCAL_OPERATION_MSG, $LOCAL_OPERATION_OK, $NEW_TEST_JOB_MSG,
#     $UPDATE_TEST_JOB, $NEW_MOVE_TABLE_MSG, $UPDATE_MOVE_TABLE,
#     $SCRAPPED_WAFERS, $PROBE_SCRAPPED, $ON_HOLD_WAFERS, $PROBE_ON_HOLD, %W
###############################################################################
sub build_confirm_settings {
    my ($parent) = @_;

    $W{'update'} = $W{$parent}->Frame();
    # Confirm Settings Heading
    $W{'update'}->Label(
        -text => $PrbLocale::Msg{'confirm_settings'},
    )->pack();
    # Local Operation - may be required for network fault tolerance
    my $local_oper_frame = $W{'update'}->Frame()->pack(
        -fill   => 'x',
        -expand => 1,
    );
    $local_oper_frame->Label(
        -textvariable => \$LOCAL_OPERATION_MSG,
    )->pack(
        -side => 'left',
        -padx => 10,
    );
    $W{'local_operation'} = $local_oper_frame->Frame();
    $W{'local_operation'}->Radiobutton(
        -text     => $PrbLocale::Msg{'yes'},
        -variable => \$LOCAL_OPERATION_OK,
        -value    => 'yes',
    )->pack(
        -side => 'left',
        -padx => 10,
    );
    $W{'local_operation'}->Radiobutton(
        -text     => $PrbLocale::Msg{'no'},
        -variable => \$LOCAL_OPERATION_OK,
        -value    => 'no',
    )->pack(
        -side => 'left',
        -padx => 10,
    );
    # Test Job Software
    my $test_job_frame = $W{'update'}->Frame()->pack(
        -fill   => 'x',
        -expand => 1,
    );
    $test_job_frame->Label(
        -textvariable => \$NEW_TEST_JOB_MSG,
    )->pack(
        -side => 'left',
        -padx => 10,
    );
    $W{'update_job'} = $test_job_frame->Frame();
    $W{'update_job'}->Radiobutton(
        -text     => $PrbLocale::Msg{'yes'},
        -variable => \$UPDATE_TEST_JOB,
        -value    => 'yes',
    )->pack(
        -side => 'left',
        -padx => 10,
    );
    $W{'update_job'}->Radiobutton(
        -text     => $PrbLocale::Msg{'no'},
        -variable => \$UPDATE_TEST_JOB,
        -value    => 'no',
    )->pack(
        -side => 'left',
        -padx => 10,
    );
    # Move Table
    my $move_table_frame = $W{'update'}->Frame()->pack(
        -fill   => 'x',
        -expand => 1,
    );
    $move_table_frame->Label(
        -textvariable => \$NEW_MOVE_TABLE_MSG,
    )->pack(
        -side => 'left',
        -padx => 10,
    );
    $W{'update_move_table'} = $move_table_frame->Frame();
    $W{'update_move_table'}->Radiobutton(
        -text     => $PrbLocale::Msg{'yes'},
        -variable => \$UPDATE_MOVE_TABLE,
        -value    => 'yes',
    )->pack(
        -side => 'left',
        -padx => 10,
    );
    $W{'update_move_table'}->Radiobutton(
        -text     => $PrbLocale::Msg{'no'},
        -variable => \$UPDATE_MOVE_TABLE,
        -value    => 'no',
    )->pack(
        -side => 'left',
        -padx => 10,
    );
    # On-Hold Wafers
    my $on_hold_frame = $W{'update'}->Frame()->pack(
        -fill   => 'x',
        -expand => 1,
    );
    $on_hold_frame->Label(
        -textvariable => \$ON_HOLD_WAFERS,
    )->pack(
        -side => 'left',
        -padx => 10,
    );
    $W{'probe_on_hold'} = $on_hold_frame->Frame();
    $W{'probe_on_hold'}->Radiobutton(
        -text     => $PrbLocale::Msg{'yes'},
        -variable => \$PROBE_ON_HOLD,
        -value    => 'yes',
    )->pack(
        -side => 'left',
        -padx => 10,
    );
    $W{'probe_on_hold'}->Radiobutton(
        -text     => $PrbLocale::Msg{'no'},
        -variable => \$PROBE_ON_HOLD,
        -value    => 'no',
    )->pack(
        -side => 'left',
        -padx => 10,
    );
    # Scrapped Wafers
    my $scrapped_frame = $W{'update'}->Frame()->pack(
        -fill   => 'x',
        -expand => 1,
    );
    $scrapped_frame->Label(
        -textvariable => \$SCRAPPED_WAFERS,
    )->pack(
        -side => 'left',
        -padx => 10,
    );
    $W{'probe_scrapped'} = $scrapped_frame->Frame();
    $W{'probe_scrapped'}->Radiobutton(
        -text     => $PrbLocale::Msg{'yes'},
        -variable => \$PROBE_SCRAPPED,
        -value    => 'yes',
    )->pack(
        -side => 'left',
        -padx => 10,
    );
    $W{'probe_scrapped'}->Radiobutton(
        -text     => $PrbLocale::Msg{'no'},
        -variable => \$PROBE_SCRAPPED,
        -value    => 'no',
    )->pack(
        -side => 'left',
        -padx => 10,
    );
}

###############################################################################
# Description:
#     create Tk frame used to display setup information
# Returns:
#     nothing
# Globals:
#     $OPERATOR_NAME, $DESIGN_ID, $STEP_NAME, $DEVIATION_LABEL, $ENGR_REQUEST
#     $JOB_NAME, $TEMPERATURE, $MOVE_TABLE, %PROCESS, %W
###############################################################################
sub build_job_info {
    # a lot of copy and paste, try to refactor
    my ($parent) = @_;
    $W{'job_info'} = $W{$parent}->Frame();
    unless ($NO_OPERATOR_REQUIRED) {
        # Operator:
        my $oper_frame = $W{'job_info'}->Frame()->pack(
            -fill => 'x',
        );
        $oper_frame->Label(
            -text  => $PrbLocale::Msg{'operator_name'},
        )->pack(
            -side   => 'left',
            -anchor => 'e',
            -padx   => 10,
        );
        $oper_frame->Label(
            -textvariable => \$OPERATOR_NAME,
        )->pack(
            -side   => 'right',
            -anchor => 'w',
            -padx   => 10,
            -fill => 'x',
        );
    }
    if ($OPT{'independent'}) {
        return;  # added to support Laser and scrubber - the remaining fields are not applicable
    }
    # Design:
    my $design_frame = $W{'job_info'}->Frame()->pack(
        -fill => 'x',
    );
    $design_frame->Label(
        -text  => $PrbLocale::Msg{'design'},
    )->pack(
        -side   => 'left',
        -anchor => 'e',
        -padx   => 10,
    );
    $design_frame->Label(
        -textvariable => \$DESIGN_ID,
    )->pack(
        -side   => 'right',
        -anchor => 'w',
        -padx   => 10,
        -fill => 'x',
    );
    # Step:
    my $step_frame = $W{'job_info'}->Frame()->pack(
        -fill => 'x',
    );
    $step_frame->Label(
        -text  => $PrbLocale::Msg{'step'},
    )->pack(
        -side   => 'left',
        -anchor => 'e',
        -padx   => 10,
    );
    $step_frame->Label(
        -textvariable => \$STEP_NAME,
    )->pack(
        -side   => 'right',
        -anchor => 'w',
        -padx   => 10,
        -fill => 'x',
    );
    # Process ID:
    my $pid_frame = $W{'job_info'}->Frame()->pack(
        -fill => 'x',
    );
    $pid_frame->Label(
        -text  => $PrbLocale::Msg{'process_id'},
    )->pack(
        -side   => 'left',
        -anchor => 'e',
        -padx   => 10,
    );
    $pid_frame->Label(
        -textvariable => \$PROCESS_STEP{'pid'},
    )->pack(
        -side   => 'right',
        -anchor => 'w',
        -padx   => 10,
        -fill => 'x',
    );
    # Deviation: I would like to only show if there is a deviation
    my $deviation_frame = $W{'job_info'}->Frame()->pack(
        -fill => 'x',
    );
    $deviation_frame->Label(
        -textvariable => \$DEVIATION_LABEL,
    )->pack(
        -side   => 'left',
        -anchor => 'e',
        -padx   => 10,
    );
    $deviation_frame->Label(
        -textvariable => \$ENGR_REQUEST,
    )->pack(
        -side   => 'right',
        -anchor => 'w',
        -padx   => 10,
        -fill => 'x',
    );
    # Test Job
    my $job_frame = $W{'job_info'}->Frame()->pack(
        -fill => 'x',
    );
    $job_frame->Label(
        -text  => $PrbLocale::Msg{'job_name'},
    )->pack(
        -side   => 'left',
        -anchor => 'e',
        -padx   => 10,
    );
    $job_frame->Label(
        -textvariable => \$JOB_NAME,
    )->pack(
        -side   => 'right',
        -anchor => 'w',
        -padx   => 10,
        -fill => 'x',
    );
    # Temperature
    if (!$OPT{'notemp'}) {
        my $temp_frame = $W{'job_info'}->Frame()->pack(
            -fill => 'x',
        );
        $temp_frame->Label(
            -text  => $PrbLocale::Msg{'temperature'},
        )->pack(
            -side   => 'left',
            -anchor => 'e',
            -padx   => 10,
        );
        $temp_frame->Label(
            -textvariable => \$TEMPERATURE,
        )->pack(
            -side   => 'right',
            -anchor => 'w',
            -padx   => 10,
            -fill => 'x',
        );
    }
    # Move Table
    if ($LOCAL_MOVE_TABLE_DIR) {
        my $move_table_frame = $W{'job_info'}->Frame()->pack(
            -fill => 'x',
        );
        $move_table_frame->Label(
            -text  => $PrbLocale::Msg{'move_table'},
        )->pack(
            -side   => 'left',
            -anchor => 'e',
            -padx   => 10,
        );
        $move_table_frame->Label(
            -textvariable => \$MOVE_TABLE,
        )->pack(
            -side   => 'right',
            -anchor => 'w',
            -padx   => 10,
            -fill => 'x',
        );
    }
}

###############################################################################
# Description:
#     create Tk frame used to gather over-ride parameters
# Returns:
#     nothing
# Globals:
#     %OVERRIDE, %W
###############################################################################
sub build_override_entry {
    my ($parent) = @_;
    $W{'override_entry'} = $W{$parent}->Frame();
    if ($NO_OPERATOR_REQUIRED) {
        # Employee ID is needed for all overrides
        my %pack_options = (
            -side => 'right',
            -anchor => 'w',
            -padx   => 28,
        );
        build_employee_entry('override_entry', 0, %pack_options);
    }
    # Override Reason:
    my @override_options;
    foreach my $option (sort keys %PrbLocale::OverrideReasons) {
        push @override_options, $option;
    }
    my $override_reason_frame = $W{'override_entry'}->Frame()->pack(
        -fill => 'x',
    );
    $override_reason_frame->Label(
        -text  => $PrbLocale::Msg{'override_reason'},
    )->pack(
        -side   => 'left',
        -anchor => 'e',
        -padx   => 10,
    );
    $W{'override_reason'} = $override_reason_frame->BrowseEntry(
        -textvariable => \$OVERRIDE{'reason'},
        -state        => 'normal',
        -width        => 40,
        -buttontakefocus => 0,
    )->pack(
        -side   => 'right',
        -anchor => 'w',
        -padx   => 10,
        -fill => 'x',
    );
    tk_configure_options('override_reason', @override_options);
    # user can enter another reason for override
    $W{'override_reason'}->bind('<Return>', [\&tk_add_option, 'override_reason', \$OVERRIDE{'reason'}]);
    # Process ID:
    my $pid_frame = $W{'override_entry'}->Frame()->pack(
        -fill => 'x',
    );
    $pid_frame->Label(
        -text  => $PrbLocale::Msg{'process_id'},
    )->pack(
        -side   => 'left',
        -anchor => 'e',
        -padx   => 10,
    );
    $W{'override_pid_list'} = $pid_frame->BrowseEntry(
        -textvariable => \$OVERRIDE{'process'},
        -state        => 'normal',
        -width        => 40,
        -buttontakefocus => 0,
    )->pack(
        -side   => 'right',
        -anchor => 'w',
        -padx   => 10,
        -fill => 'x',
    );
    # Test Job
    my $job_frame = $W{'override_entry'}->Frame()->pack(
        -fill => 'x',
    );
    $job_frame->Label(
        -text  => $PrbLocale::Msg{'job_name'},
    )->pack(
        -side   => 'left',
        -anchor => 'e',
        -padx   => 10,
    );
    $W{'override_job_list'} = $job_frame->BrowseEntry(
        -textvariable => \$OVERRIDE{'job_name'},
        -width        => 40,    # to align with process id Browse Entry
        -buttontakefocus => 0,
    )->pack(
        -side   => 'right',
        -anchor => 'w',
        -padx   => 10,
        -fill => 'x',
    );
    # Other Required Parameters:
    foreach my $param_name (keys %{$PrbCfg::PlatformCfg{'RequiredParams'}}) {
        my $param_frame = $W{'override_entry'}->Frame()->pack(
            -fill => 'x',
        );
        $param_frame->Label(
            -text  => $param_name,
        )->pack(
            -side   => 'left',
            -anchor => 'e',
            -padx   => 10,
        );
        $param_frame->Entry(
            -textvariable => \$OVERRIDE{$param_name},
            -class        => 'parameter',
        )->pack(
            -side   => 'right',
            -anchor => 'w',
            -padx   => 10,
            -fill => 'x',
        );
    }
    # configure BrowseEntry bindings to make it easier to select options
    $W{'override_pid_list'}->bind('<FocusOut>', [ \&AutoCompleteBrowseEntry, 'override_pid_list', \$OVERRIDE{'process'} ]);
    $W{'override_pid_list'}->bind('<KeyPress>', [ \&BrowseEntryKeyHandler, 'override_pid_list', Ev("A"), Ev("K"), \$OVERRIDE{'process'} ]);
    $W{'override_pid_list'}->Subwidget('slistbox')->bind('<KeyPress>', [ \&BrowseEntryKeyHandler, 'override_pid_list', Ev("A"), Ev("K"), \$OVERRIDE{'process'} ]);
    # same as above for Job Name
    $W{'override_job_list'}->bind('<FocusOut>', [ \&AutoCompleteBrowseEntry, 'override_job_list', \$OVERRIDE{'job_name'} ]);
    $W{'override_job_list'}->bind('<KeyPress>', [ \&BrowseEntryKeyHandler, 'override_job_list', Ev("A"), Ev("K"), \$OVERRIDE{'job_name'} ]);
    $W{'override_job_list'}->Subwidget('slistbox')->bind('<KeyPress>', [ \&BrowseEntryKeyHandler, 'override_job_list', Ev("A"), Ev("K"), \$OVERRIDE{'job_name'} ]);
}

###############################################################################
# Description:
#     perform any cleanup when Tk application shuts down
# Returns:
#     nothing
# Globals:
#     none
###############################################################################
sub cleanup {
    # perform any shutdown activities then die
    notify('debug', join("\n", @FUNCTION_TRACE));
    if ($OPT{'debug'}) {
        close(DEBUG_FILE);
    }
    exit(0);
}

###############################################################################
# Description:
#     used to cleanup old Test Jobs, attribute files, etc.
# Returns:
#     array of directory paths removed
# Globals:
#     none
###############################################################################
sub cleanup_old_directories {
    my ($directory, $age_in_days, @excludes) = @_;
    my $pattern = qw(^[^\.].+$);
    my @removed_paths;
    my ($status, @files) = find_files($directory, $pattern);
    my $now = time();
    notify('debug', "Cleaning directory: $directory");
    foreach my $path (@files) {
        my $filename = basename($path);
        if (!grep /^${filename}$/, @excludes) {
            my $path_stat = stat($path);
            my $last_accessed;
            # On Unix/Linux atime is appropriate for files, but not directories
            # ls will update a directories atime, but not a files atime
            # mtime should be used for directories on Unix/Linux/Windows
            $last_accessed = int(($now - $path_stat->mtime)/86400);
            if ($path_stat and ($last_accessed > $age_in_days) and (-d $path)) {
                if ($status = remove_directory($path)) {
                    notify('log', "ERROR removing '$path' : $status");
                } else {
                    push @removed_paths, $path;
                    notify('debug', "removed '$path' last accessed $last_accessed days ago");
                }
            }
        }
    }
    return(@removed_paths);
}

###############################################################################
# Description:
#     used to cleanup old Test Job archives
# Returns:
#     non-zero value for error
# Globals:
#     none
###############################################################################
sub cleanup_old_archives {
    my ($archive_dir, @jobs_to_remove) = @_;
    # this was added to remove job archives as the uncompressed directory is removed
    my @archived_jobs;
    my $find_status;
    my @find_list;
    foreach my $job_path (@jobs_to_remove) {
        my $job_pattern = qw/^(\d{10}_)?/ . basename($job_path) . qw(\.(tgz|zip|tar\.gz)$);
        ($find_status, @find_list) = find_files($archive_dir, $job_pattern);
        if (!$find_status) {
            foreach my $job_archive (@find_list) {
                push @archived_jobs, $job_archive;
            }
        }
    }
    if (scalar @archived_jobs) {
        return(remove_files(@archived_jobs));
    } else {
        return(undef);
    }
}

###############################################################################
# Description:
#     calls Equipment Tracking to obtain equipment information
# Returns:
#     nothing
# Globals:
#     $TESTER_ID, $NO_CHILD_EQUIPMENT, %ET_ITEMS, %ET_STATE, %LOAD_PORT
###############################################################################
sub get_equip_info {
    time_it('get_equip_info');
    my ($status, $reply) = get_probe_cell_info(\%ET_ITEMS, \%ET_STATE, $OPT{'site'}, $MESSRV, $SITE_CFG{'Facility'}{$OPT{'site'}}, $TESTER_ID);
    if ($status) {
        fatal_startup_error(PrbLocale::et_error($TESTER_ID, $reply));
    } else {
        my $prober_found;
        if ( !$OPT{'relation'} ) {
           $OPT{'relation'} = "LOAD|PROCESS";  # Only display lot entry boxes for a valid load port or process chamber...kbremkes
        }
        foreach my $prober (sort keys %{$ET_ITEMS{$TESTER_ID}{'child'}}) {
            if (!$OPT{'relation'} or ($ET_STATE{$TESTER_ID}{'child'}{$prober}{'relation'} =~ /$OPT{'relation'}/i)) {
                $prober_found = 1;
                if (($ET_STATE{$TESTER_ID}{'child'}{$prober}{'state'} !~ /^Non-scheduled$/i) or
                    ($ET_STATE{$TESTER_ID}{'child'}{$prober}{'sub_state'} =~ /^QUAL_RUN_NONSCHED$/i)) {
                    $LOAD_PORT{$prober}{'front'}{'status'} = 'available';
                    $LOAD_PORT{$prober}{'front'}{'lot_id'} = '';
                    $LOAD_PORT{$prober}{'front'}{'lot_type'} = '';
                    $LOAD_PORT{$prober}{'front'}{'part_type'} = '';
                    $LOAD_PORT{$prober}{'front'}{'quantity'} = 0;
                    if ($OPT{'dual'}) {
                        $LOAD_PORT{$prober}{'rear'}{'status'} = 'available';
                        $LOAD_PORT{$prober}{'rear'}{'lot_id'} = '';
                        $LOAD_PORT{$prober}{'rear'}{'lot_type'} = '';
                        $LOAD_PORT{$prober}{'rear'}{'part_type'} = '';
                        $LOAD_PORT{$prober}{'rear'}{'quantity'} = 0;
                    }
                }
            }
        }
        if (!$prober_found) {
            $NO_CHILD_EQUIPMENT = 1;
            # some equipment is not configured with child equipment
            # this will probably change when load ports are classified as children
            if (($ET_STATE{$TESTER_ID}{'state'} !~ /^Non-scheduled$/i) or
                ($ET_STATE{$TESTER_ID}{'sub_state'} =~ /^QUAL_RUN_NONSCHED$/i)) {
                $LOAD_PORT{$TESTER_ID}{'front'}{'status'} = 'available';
                $LOAD_PORT{$TESTER_ID}{'front'}{'lot_id'} = '';
                $LOAD_PORT{$TESTER_ID}{'front'}{'lot_type'} = '';
                $LOAD_PORT{$TESTER_ID}{'front'}{'part_type'} = '';
                $LOAD_PORT{$TESTER_ID}{'front'}{'quantity'} = 0;
            }
        } else {
            undef $NO_CHILD_EQUIPMENT;
        }
        notify('debug', Data::Dumper->Dump([\%ET_ITEMS, \%ET_STATE], [qw(*ET_ITEMS *ET_STATE)]));
    }
    time_it('get_equip_info', 'end');
}

###############################################################################
# Description:
#     sends messages to operator, stdout, or log file
# Returns:
#     nothing
# Globals:
#     %OPT, %W
###############################################################################
sub notify {
    my ($verbosity, @message) = @_;
    my $epoch = time();
    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($epoch);
    my $timestring = sprintf("%d-%02d-%02d_%02d:%02d:%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec);
    if ($verbosity eq 'warn') {
        foreach my $msg(@message){
           send_alarm_to_ET($msg);        
        }
        $W{'status'}->Busy();
        $W{'status'}->delete('1.0', 'end');
        if ($ENCODING) {
            # the encoding allows utf8 to be displayed on Solaris systems
            $W{'status'}->insert('end', encode($ENCODING, "@message"));
        } else {
            $W{'status'}->insert('end', @message);
        }
        $W{'status'}->configure(
            -background => $PrbLocale::Color{'warning_bg'},
            -foreground => $PrbLocale::Color{'warning_fg'},
        );
        $W{'status'}->Unbusy();
        if ($OPT{'notk'}) {
            # display error message, then exit
            print STDERR "@message\n";
            tk_cancel();
        }
        else {            
            if (open(WARNLOG, ">>${WARN_FILE}")) {
                print WARNLOG "$timestring @message\n";
                close(WARNLOG);        
            }
        }            
    } elsif ($verbosity eq 'info') {
        $W{'status'}->Busy();
        $W{'status'}->delete('1.0', 'end');
        if ($ENCODING) {
            $W{'status'}->insert('end', encode($ENCODING, "@message"));
        } else {
            $W{'status'}->insert('end', @message);
        }
        $W{'status'}->configure(
            -background => $W{'default_bg'},
            -foreground => $W{'default_fg'},
        );
        $W{'status'}->Unbusy();
    } elsif ($verbosity eq 'log') {
        if (-f $LOG_FILE and !-w  $LOG_FILE) {
            # log file exists but is not writable
            unlink $LOG_FILE;
        }
        if (open(APPLICATIONLOG, ">>${LOG_FILE}")) {
            print APPLICATIONLOG "$timestring @message\n";
            close(APPLICATIONLOG);
        } else {
            print "$timestring @message\n";
        }
    } 
    if ($DEBUG_MODE and ($verbosity =~ /debug|info|log|warn/i)) {
        print DEBUG_FILE "[$timestring]:[$verbosity]:@message\n";
    }
}

#########################################################################
#  Description:
#     Send generic menu alarm to ET
#  Returns:
#     1 if alarm set, otherwise 0
###############################################################################
sub send_alarm_to_ET{
   my $alarm_txt = shift;

   # scrub alarm message length and special characters
   $alarm_txt = substr($alarm_txt,0,254);
   $alarm_txt =~ s/\<|\>|\'|\"//g;

   if($alarm_txt && defined ($PCONTROLEVENT) && (-e $PCONTROLEVENT)){
      my $cmd = "$PCONTROLEVENT -tester=$TESTER_ID -event=ALARM_SET -alarm=MENU_ERROR -alarm_text=\"$alarm_txt\"";
      notify("log",$cmd);
      system($cmd);
      return 1;
   }
   return 0;
}

###############################################################################
# Description:
#     sends important information to support personnel
# Returns:
#     nothing
###############################################################################
sub notify_important {
    my ($severity, $subject, $message, @send_to) = @_;

    if (!@send_to) {
        notify('log', "notify_important called with empty \@send_to, unable to deliver '$message'");
    } elsif ($OPT{'offline'}) {
        notify('debug', "OFFLINE_MESSAGE_NOT_SENT $severity @send_to $message");
    } elsif ($severity eq 'mail') {
        my $obj = Micron::Mail->new($message);
        $obj->SetSubject($subject);
        $obj->SetToList(@send_to);
        $obj->SendTextEmail();
        notify('log', "mailto:@send_to $message");
    } elsif ($severity eq 'page') {
        my $obj = Micron::Page->new($message);
        $obj->SetToList(@send_to);
        $obj->SendPage();
        notify('log', "page:@send_to $message");
    }
}

###############################################################################
# Description:
#     validates operator ID
# Returns:
#     localized error message on failure
# Globals:
#     $OPERATOR_ID, $OPERATOR_NAME, %OPT
###############################################################################
sub validate_operator {
    if (!$OPERATOR_ID) {
        return($PrbLocale::Error{'oper_required'});
    } else {
        my ($GivenName, $SurName, $Error, $ErrorText);
        eval {
            my $Worker = Micron::MTGroups::CMTWorker->new();
            if ($Worker->IsValidWorkerNumber(int $OPERATOR_ID)) {
                $GivenName = $Worker->GetGivenName();
                $SurName = $Worker->GetSurName();
                $EMPLOYEE_NAME = $Worker->GetUserName();
            } else {
                $Error = $Worker->GetErrorStatusCode();
                $ErrorText = $Worker->GetErrorStatusText();
            }
        };
        if ($@) {
            return(PrbLocale::oper_error($@));
        } elsif (!$GivenName and !$SurName) {
            return(PrbLocale::oper_error($ErrorText));
        } else {
            $OPERATOR_NAME = PrbLocale::format_name($GivenName, $SurName);
        }
    }
    return(undef);
}

###############################################################################
# Description:
#     if enough data has been supplied via command line arguments or by other
#     automated means, this function will allow an automatic start
# Returns:
#     this function will not return if all data has been provided
#     and no errors are detected
# Globals:
#     $AUTO_START, %LOAD_PORT, %OPT
###############################################################################
sub check_for_minimum_data {
    my $lot_found;
    my $any_error;
    foreach my $prober (keys %LOAD_PORT) {
        foreach my $cassette (keys %{$LOAD_PORT{$prober}}) {
            if (($LOAD_PORT{$prober}{$cassette}{'status'} eq 'available') and
                 $LOAD_PORT{$prober}{$cassette}{'lot_id'}) {
                $lot_found = 1;
            }
        }
    }
    if (!$NO_OPERATOR_REQUIRED and !validate_operator()) {
        # operator is not valid - display the Graphical Interface
    } elsif ($lot_found) {
        $AUTO_START = 1;
        $W{'next'}->invoke();
        # if all user items have been provided on the command line, and the user
        # is not required or allowed to edit the setup, we won't get this far
        # however, if user input is required we will show the Graphical Interface
        undef $AUTO_START;
        show_main_window() if $OPT{'notk'};
    }
}

###############################################################################
# Description:
#     validates information provided in 'oper_entry' page
#     (i.e. operator [optional], lot ID, probe card information)
#     in Batch Stage Controller mode it will validate the lot by obtaining
#     the batch information but will update to latest MES attributes
#     if that fails, and override/bypass options are specified
#     or when not in Batch Stage Controller mode, MES lot validation is used
# Returns:
#     nothing
# Globals:
#     $OPERATOR_ID, $OPERATOR_NAME, $BSC_MODE
#     $DESIGN_ID, $STEP_NAME, $GERM_PID_EXPECTED, $TESTER_ID, $INSTRUCTIONS
#     %PROCESS_LIST, %PCARD_ID, %EQUIP_STATE_ALLOW
#     %PCARD_DATA, %PCARD_SUMMARY, %OVERRIDE, %LOAD_PORT, %ET_STATE, %MES_ATTR,
#     %MES_META, %GERM_EQUIP_PARAM, %GERM_EQUIP_META, %OPT, %W
###############################################################################
sub tk_validate_lots {
    push @FUNCTION_TRACE, "tk_validate_lots()";
    my $any_error;
    my ($status, $response);
    my ($attr_ref, $lot_meta, $wfr_attr, $wfr_meta);
    my ($recipe_param, $recipe_meta, $germ_equip_index); # from get_all_batches
    my %lots;       # hash used to avoid redundant calls for lot split across heads
    my %setup_prober; # hash used to avoid unnecessary calls to PCT
    my $test_job_choices_ref;     # for GeRM over-ride
    my $batch_found;# flag indicating a batch exists
    unless ($NO_OPERATOR_REQUIRED) {
        $any_error = validate_operator();
    }
    foreach my $prober (keys %LOAD_PORT) {
        foreach my $cassette (keys %{$LOAD_PORT{$prober}}) {
            if (($LOAD_PORT{$prober}{$cassette}{'status'} eq 'available') and
                 $LOAD_PORT{$prober}{$cassette}{'lot_id'}) {
                # the lot must be placed on the correct prober in Batch Stage Controller mode
                push @{$lots{$LOAD_PORT{$prober}{$cassette}{'lot_id'}}}, $prober;
                push @{$setup_prober{$prober}}, $LOAD_PORT{$prober}{$cassette}{'lot_id'};
            }
        }
    }
    refresh_setup_options();  # update global variable
    if (!(keys %lots)) {
        $any_error .= "\n" if $any_error;
        $any_error .= $PrbLocale::Error{'lot_required'};
    } elsif ($OVERRIDE{'requested'} and !$EQUIP_STATE_ALLOW{'override'}) {
        $any_error .= "\n" if $any_error;
        $any_error .= $PrbLocale::Error{'override_fail'};
    } else {
        # some refactoring is possible
        if (!$any_error and $OPT{'bsc'}) {
            notify('info', $PrbLocale::Msg{'calling_bsc'});
            ($status, $batch_found, $recipe_param, $recipe_meta, $germ_equip_index) = get_all_batches(%lots);
            if ($status) {
                $any_error .= "\n" if $any_error;
                $any_error .= $status;
            }
        }
        # to work around batch caching and for legacy validation
        if (!$any_error) {
            # to skip the hold check
            # Operator ID is required, Equipment must be in an Engineering State, ALLOW_HOLD must be specified
            # and only non-Production process ID's (checked later) may be selected
            # obtain lot information from MES
            notify('info', $PrbLocale::Msg{'calling_mes'});
            foreach my $lot_id (keys %lots) {
                ($status, $attr_ref, $lot_meta) = get_mes_attributes($lot_id);
                # some of this logic is duplicated in get_all_batches, refactor is desirable
                my $catalog_lot = (!$status and (defined ${$attr_ref}{'PROBE CATALOG LOT'}) and (${$attr_ref}{'PROBE CATALOG LOT'}[0] eq 'YES')) ? 1 : 0;
                if ( $status ) {
                    $any_error .= "\n" if $any_error;
                    $any_error .= PrbLocale::mes_error($lot_id, $attr_ref);
                # per drace and djlopez allow 'PROBE CATALOG LOT' to probe when it is on hold
                # this is due to business rules associated with catalog lots that require them
                # to be re-scrapped after they have been released from hold to be placed back
                # on Hold-Catalog
                # no other lot types may be probed while on hold
                # a simpler check is to exclude Hold-Catalog, since that would by definition
                # be a catalog lot, however, a lot can be in the catalog system and be on a
                # regular hold, this is why drace suggested the more complicated logic below

                # in addition drace said it is OK to allow catalog lots to be probed without
                # requiring track-in
                # bypass the on-hold check if we are testing offline and ALLOW_HOLD is specified
                # bypass the must be tracked check if we are testing offline and NO_TRACK_CHECK is specified
                
                # Moved/renamed the lot hold check to only check if the lot is actually on hold.  
                # Then test additional requirements which are:
                # the Lot is on hold and is not a catalog lot
                # The tool is in an Engineering state  ie $EQUIP_STATE_ALLOW{'hold'} = 'ENGINEERING'
                # A valid operator ID was entered
                # The operator ID is in a valid MTGroup or the option to ALLOW_HOLD was passed in the command line.
                } elsif ((${$lot_meta}{'StateDesc'} =~ /Hold/i) and !$catalog_lot) {
                    my $allow_lot_on_hold = 0;
                    my $Username = "";
                    if ( ($EQUIP_STATE_ALLOW{'hold'} or $OPT{'offline'}) and !$NO_OPERATOR_REQUIRED) {
                        MTGroupWorkerNoToUsername( $OPERATOR_ID , $Username );
                        foreach my $group (@{$SITE_CFG{'ALLOW_HOLD_MTGROUPS'}{$OPT{'site'}}}) {              
                            if ( MTGroupValidMember ( $Username , $group ) ) {  #added for BAMS #1060
                                $allow_lot_on_hold = 1;
                                last;
                            }
                        }
                        $allow_lot_on_hold = 1 if $OPT{'ALLOW_HOLD'};
                    }
                    if (!$allow_lot_on_hold)
                    {
                        $any_error .= "\n" if $any_error;
                        $any_error .= PrbLocale::lot_hold($lot_id, ${$lot_meta}{'StateDesc'});
                    }
                } elsif (!$batch_found and !$OVERRIDE{'requested'} and !$catalog_lot and (${$lot_meta}{'TravStep'}{'TrackInFlag'} =~ /Y/i) and (${$lot_meta}{'TrackInFlag'} =~ /N/i) and !($OPT{'offline'} and $OPT{'NO_TRACK_CHECK'})) {
                    $any_error .= "\n" if $any_error;
                    $any_error .= PrbLocale::lot_not_tracked_in($lot_id, ${$lot_meta}{'StepName'});
                }
                if (!$any_error) {
                    # MES information may have been obtained from BatchRetrieve but it is cached, so some items
                    # (most important the values used for interrupt recovery) may have changed
                    $MES_ATTR{$lot_id} = $attr_ref;
                    $MES_META{$lot_id} = $lot_meta;
                }
            }
        }
    }
    if (!$any_error) {
        my %design_ids; # hash used to check for multiple design id's
        my %step_names; # hash used to check for multiple steps
        foreach my $lot_id (keys %lots) {
            $DESIGN_ID = $MES_META{$lot_id}{'DesignId'};
            $STEP_NAME = $MES_META{$lot_id}{'StepName'};
            # arrays are used for error reporting
            push @{$design_ids{$DESIGN_ID}}, $lot_id;
            push @{$step_names{$STEP_NAME}}, $lot_id;
        }
        notify('debug', Data::Dumper->Dump([\%MES_ATTR, \%MES_META], [qw(*MES_ATTR *MES_META)]));
        $GERM_PID_EXPECTED = ($OPT{'pid_germ'} or $batch_found or ($TRACKING_REQUEST_STEP eq $STEP_NAME)) ? 1 : 0;
        # verify there is a valid Process for this step
        if (!$OVERRIDE{'requested'} and !$GERM_PID_EXPECTED and !scalar keys %{$PROCESS_LIST{$STEP_NAME}}) {
            $any_error .= "\n" if $any_error;
            $any_error .= PrbLocale::no_process_error($STEP_NAME);
        }
        # verify all lots have the same design_id
        if (!$OPT{'independent'} and (1 != (scalar keys %design_ids))) {
            $any_error .= "\n" if $any_error;
            $any_error .= PrbLocale::multiple_design_ids(%design_ids);
        }
        # verify all lots have the same tracking step
        if (!$OPT{'independent'} and (1 != (scalar keys %step_names))) {
            $any_error .= "\n" if $any_error;
            $any_error .= PrbLocale::multiple_steps(%step_names);
        }
    }
    if (!$any_error and !$NO_PROBECARD) {
        time_it('read_card_id');
        notify('info', $PrbLocale::Msg{'calling_pct'});
        # Note:
        #    There is no physical reason to prevent different bond pad materials from being introduced on dual
        #    cassette systems at the same time, however we only want to make one call to PCT to get cleaning
        #    recipe and material dependent overtravel settings (that could be changed if needed, or PCT could
        #    be changed to return information for all or specified bond pad materials)
        #
        #    GPC "currently" expects to read probecard info including recipe from a probecard[0|1].asc file, and there
        #    is only one file per head.  This could be easily changed to obtain the information from the lot traveler
        #    which should be dual cassette capable.
        #
        #    Unfortunately the PCT_START_CARD message which previously changed the card state when a lot was
        #    introduced (similar to Equipment state change) was modified to also change the current card contamination state
        #    That is unfortunate, because it doesn't accurately reflect the current probing state in a Cascaded
        #    lot situation.  That could be fixed by setting the Contamination state at lot start time from the event handler.
        foreach my $prober (keys %setup_prober) {
            my %bond_pad_material; # hash used to check for multiple bond pad material
            foreach my $lot_id (@{$setup_prober{$prober}}) {
                my $bond_pad_from_attribute = $MES_ATTR{$lot_id}{'CU BOND PAD TYPE'}[0] ? $MES_ATTR{$lot_id}{'CU BOND PAD TYPE'}[0] : 'MISSING';
                push @{$bond_pad_material{$bond_pad_from_attribute}}, $lot_id;
            }
            if (1 != (scalar keys %bond_pad_material)) {
                $any_error .= "\n" if $any_error;
                $any_error .= PrbLocale::mixed_bond_pad_error(%bond_pad_material);
            } else {
                # conditional operator allows for offline testing
                my $card_id = defined $PCARD_ID{$prober} ? $PCARD_ID{$prober} : PrbCfg::read_card_id($prober);
                if (! defined $card_id) {
                    $any_error .= "\n" if $any_error;
                    $any_error .= PrbLocale::card_read_error($prober);
                } elsif ($card_id !~ /^\d+$/) {
                    # if the card_id is non-numeric it is likely there was an error reading the card
                    $any_error .= "\n" if $any_error;
                    $any_error .= PrbLocale::card_read_error($prober, $card_id);
                } else {
                    # obtain probe card information from PCT
                    my $lookup_bond_pad_material = GetContamType( (keys %bond_pad_material)[0] );
                    ($status, $response) = get_probecard_data($card_id, $prober, $lookup_bond_pad_material);
                    if ( $status ) {
                        $any_error .= "\n" if $any_error;
                        $any_error .= PrbLocale::pct_error($card_id, $response);
                    } else {
                        $PCARD_ID{$prober} = $card_id;
                        $PCARD_DATA{$prober} = $response;
                        $PCARD_SUMMARY{$prober}{'description'} = "$PCARD_DATA{$prober}{'x_parallelism_no'} X $PCARD_DATA{$prober}{'y_parallelism_no'} $PCARD_DATA{$prober}{'vendor_name'}";
                        $PCARD_SUMMARY{$prober}{'id'} = $PCARD_DATA{$prober}{'equip_id'};
                        $PCARD_SUMMARY{$prober}{'name'} = $PCARD_DATA{$prober}{'probe_card_type_code'};
                    }
                }
            }
            time_it('read_card_id', 'end');
        }
        notify('debug', Data::Dumper->Dump([\%PCARD_DATA], [qw(*PCARD_DATA)]));
    }
    if ($any_error) {
        notify('warn', $any_error);
    } else {
        notify('info', '');
        refresh_lot_info();
        # calling configure_pid_selections has a side effect of setting $PROCESS{'production'}
        configure_pid_selections($STEP_NAME, undef);
        my $command_line_supplied_process;
        if ($OPT{'pid'}) {
            my $apparent_step = lookup_tracking_step($OPT{'pid'}, $STEP_NAME);
            if ($apparent_step) {
                $command_line_supplied_process = "$OPT{'pid'} - $PROCESS_LIST{$apparent_step}{$OPT{'pid'}}{'ProcessDesc'}";
            }
        }
        if ($command_line_supplied_process and (grep /^$command_line_supplied_process$/, ($W{'pid_list'}->choices))) {
            $PROCESS{'selected'} = $command_line_supplied_process;
            tk_pid_selected();
        } elsif ($EQUIP_STATE_ALLOW{'mode_select'} or !$GERM_PID_EXPECTED) {
            # operator is required to select the Process ID
            $AUTO_START = 0;
        }
        if ($batch_found) {
            $INSTRUCTIONS = undef;
            # Note: BSC returns recipe parameters for each prober
            # potentially this can be useful
            # prior to BSC we stored recipe information only for the mainframe
            # this will be maintained at this time to avoid changes to all
            # the platform specific config files, unfortunately, this will
            # probably make it harder to transition later - in a time crunch now
            foreach my $prober (keys %setup_prober) {
                foreach my $lot_id (@{$setup_prober{$prober}}) {
                    my $card_config = $NO_PROBECARD ? 'none' : $PCARD_DATA{$prober}{'bit_config_id'};
                    my $equip_index = ${$germ_equip_index}{$prober}{$lot_id};
                    $GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_index} = ${$recipe_param}{$lot_id}{$equip_index};
                    $GERM_EQUIP_META{$card_config}{$lot_id}{$equip_index} = ${$recipe_meta}{$lot_id}{$equip_index};
                    if ($GERM_EQUIP_META{$card_config}{$lot_id}{$equip_index}{'instructions'}) {
                        if ($OPT{'independent'}) {
                            # load ports may have different instructions, display all available
                            $INSTRUCTIONS .= "\n" if $INSTRUCTIONS;
                            $INSTRUCTIONS .= "$prober : $lot_id : $GERM_EQUIP_META{$card_config}{$lot_id}{$equip_index}{'instructions'}";
                        } elsif (!$INSTRUCTIONS or ($INSTRUCTIONS !~ /$GERM_EQUIP_META{$card_config}{$lot_id}{$equip_index}{'instructions'}/)) {
                            # add new instructions but don't duplicate existing instructions
                            $INSTRUCTIONS .= "\n" if $INSTRUCTIONS;
                            $INSTRUCTIONS .= $GERM_EQUIP_META{$card_config}{$lot_id}{$equip_index}{'instructions'};
                        }
                    }
                }
            }
            notify('debug', Data::Dumper->Dump([\%GERM_EQUIP_PARAM, \%GERM_EQUIP_META, \$INSTRUCTIONS], [qw(*GERM_EQUIP_PARAM *GERM_EQUIP_META *INSTRUCTIONS)]));
            # verify setup information and obtain probe information
            $BSC_MODE = 1;
            tk_validate_recipe();
        } elsif ($OVERRIDE{'requested'}) {
            my $job_wildcard = $OPT{'job'} ? $OPT{'job'} : $DESIGN_ID;
            ($status, $test_job_choices_ref) = tk_build_job_list($job_wildcard, $JOB_RELEASE_SERVER, $LOCAL_JOB_DIR);
            if ($status) {
                $any_error .= "\n" if $any_error;
                $any_error .= $test_job_choices_ref;
                notify('warn', $any_error);
            } else {
                # acameron is reluctant to make over-ride any easier,
                # but has capitulated due to requests from multiple sites
                @{$test_job_choices_ref} = sort @{$test_job_choices_ref};
                # the eval below allows platform specific sorting of the Test Jobs
                eval {
                    PrbCfg::sort_job_names(\@{$test_job_choices_ref});
                };
                tk_configure_options('override_job_list', @{$test_job_choices_ref});
                # pre-populate override defaults if provided
                if ($OPT{'job'} and (grep /^$OPT{'job'}$/, @{$test_job_choices_ref})) {
                    $OVERRIDE{'job_name'} = $OPT{'job'};
                }
                if ($OPT{'reason'}) {
                    if (defined $PrbLocale::OverrideReasons{$OPT{'reason'}}) {
                        $OVERRIDE{'reason'} = $PrbLocale::OverrideReasons{$OPT{'reason'}};
                    } else {
                        $OVERRIDE{'reason'} = $OPT{'reason'};
                    }
                }
                if ($OPT{'move_table'}) {
                    # if $PrbCfg::PlatformCfg{'RequiredParams'}{'MOVE_TABLE_NAME'} is defined the user
                    # will be given a chance to edit what was specified on the command line
                    $OVERRIDE{'MOVE_TABLE_NAME'} = $OPT{'move_table'};
                }
                $OVERRIDE{'process'} = ($command_line_supplied_process) ? $command_line_supplied_process : $PROCESS{'production'};
                if (defined $OPT{'temp'} and (defined $PrbCfg::PlatformCfg{'RequiredParams'}{'Temperature'})) {
                    # for backward compatibility Temperature is specified by Test Job in override
                    # this allows the Temperature to be specified on the command line,
                    # but only if it is also visible and hence changeable by the operator
                    $OVERRIDE{'Temperature'} = $OPT{'temp'};
                }
                $OPERATOR_ID = undef unless $OPERATOR_ID;
                page_to('override_entry');
                if ($AUTO_START) {
                    $W{'next'}->configure(-state => 'normal',);  # tk_configure_callback manages disable/enable
                    $W{'next'}->invoke();
                }
            }
        } elsif ($GERM_PID_EXPECTED) {
            # obtain the recipe from GeRM, page_to('process_entry') may occur later
            tk_get_recipe();
        } else {
            page_to('process_entry');
            if ($AUTO_START) {
                $W{'next'}->configure(-state => 'normal',);  # tk_configure_callback manages disable/enable
                $W{'next'}->invoke();
            }
        }
    }
}

###############################################################################
# Description:
#     this function was extracted from tk_validate_lots
#     when batches were obtained for each lot, like get_mes_attributes
#     but now we need to obtain all the batches assigned to an equipment
#     this made the logic messy, some restructuring is needed
# Returns:
#     non-zero localized error message
#     non-zero if a batch is found
#     globals are used to return most of the data
# Globals:
#     $TESTER_ID, $NO_CHILD_EQUIPMENT
#     %LOAD_PORT, %OPT, %OVERRIDE, %MES_ATTR, %MES_META
###############################################################################
sub get_all_batches {
    my (%lots) = @_;
    my ($warning, $any_error);
    my ($status);
    my ($attr_ref, $lot_meta, $recipe_param, $recipe_meta, $batch_meta);
    my ($one_lot_attr_ref, $one_lot_lot_meta, $one_lot_recipe_param, $one_lot_recipe_meta, $one_lot_batch_meta);
    my $batch_found;# flag indicating a batch exists
    my $germ_equip_index; # added to support re-order of logic for auto card contamination switching - there may be an easier way
    ($status, $attr_ref, $lot_meta, $recipe_param, $recipe_meta, $batch_meta) = get_batch_information();
    if ($status) {
        $any_error .= "\n" if $any_error;
        $any_error .= PrbLocale::bsc_equip_query_error($TESTER_ID, $status);
    }
    foreach my $lot_id (keys %lots) {
        my $child_staged;          # flag indicates lot staged to process chamber or load port
        my $mainframe_staged;      # flag indicates lot staged to mainframe
        if (!${$batch_meta}{$lot_id}) {
            ($status, $one_lot_attr_ref, $one_lot_lot_meta, $one_lot_recipe_param, $one_lot_recipe_meta, $one_lot_batch_meta) = get_batch_information($lot_id);
            if ( $status ) {
                if ( $status =~ /Unable to locate the Lot/i ) {
                    # this is a special case that is classified as a warning that can be bypassed
                    $warning .= "\n" if $warning;
                    $warning .= PrbLocale::bsc_error($lot_id, $status);
                } else {
                    $any_error .= "\n" if $any_error;
                    $any_error .= PrbLocale::bsc_error($lot_id, $status);
                }
            } else {
                ${$attr_ref}{$lot_id} = ${$one_lot_attr_ref}{$lot_id};
                ${$lot_meta}{$lot_id} = ${$one_lot_lot_meta}{$lot_id};
                ${$recipe_param}{$lot_id} = ${$one_lot_recipe_param}{$lot_id};
                ${$recipe_meta}{$lot_id} = ${$one_lot_recipe_meta}{$lot_id};
                ${$batch_meta}{$lot_id} = ${$one_lot_batch_meta}{$lot_id};
            }
        }
        if (!$status) {
            notify('debug', Data::Dumper->Dump([\$recipe_param, \$recipe_meta, \$batch_meta], [qw(*recipe_param *recipe_meta *batch_meta)]));
            my @selected_equipment;
            foreach my $equipment (keys %{${$recipe_meta}{$lot_id}}) {
                if ((${$recipe_meta}{$lot_id}{$equipment}{'Selected'} =~ /YES/i) and (${$recipe_meta}{$lot_id}{$equipment}{'LotId'} =~ /$lot_id/i)) {
                    $batch_found = 1;
                    if ($equipment !~ /$TESTER_ID/i) {
                        $child_staged = 1;
                        push @selected_equipment, $equipment;
                    } else {
                        $mainframe_staged = 1;
                    }
                }
            }
            if ($mainframe_staged and !$child_staged and ($OPT{'stage_to_mf'} or $NO_CHILD_EQUIPMENT)) {
                # staging to the mainframe is allowed for this equipment type, lot can be placed on any port
                (@selected_equipment) = (@{$lots{$lot_id}});
            }
            foreach my $prober (@{$lots{$lot_id}}) {
                if (scalar @selected_equipment) {
                    if (!grep /$prober/, @selected_equipment) {
                        $any_error .= "\n" if $any_error;
                        $any_error .= PrbLocale::staged_lot_load_error($lot_id, $prober, @selected_equipment);
                    }
                } else {
                    # this will be an error if any lot has been staged or we expect all lots to be staged
                    $warning .= "\n" if $warning;
                    $warning .= PrbLocale::lot_not_staged($lot_id, $prober);
                }
            }
            if (scalar @selected_equipment) {
                my (@allowed_batch_state) = ('Staged', 'Committed', 'Running');  # not 'Processed', 'Aborted'
                # this is duplicated logic and may not be necessary if we don't stage catalog
                # lots using BSC, but need to check if lots staged can be placed on hold???
                my $catalog_lot = ((defined ${$attr_ref}{$lot_id}{'PROBE CATALOG LOT'}) and (${$attr_ref}{$lot_id}{'PROBE CATALOG LOT'}[0] eq 'YES')) ? 1 : 0;
                if ((${$lot_meta}{$lot_id}{'StateDesc'} =~ /Hold/i) and !$catalog_lot) {
                    $any_error .= "\n" if $any_error;
                    $any_error .= PrbLocale::lot_hold($lot_id, ${$lot_meta}{$lot_id}{'StateDesc'});
                } elsif ($OVERRIDE{'bsc_bypass'} or $OVERRIDE{'requested'}) {
                    $any_error .= "\n" if $any_error;
                    $any_error .= PrbLocale::override_staged_lot($lot_id);
                } elsif (!grep /^${$batch_meta}{$lot_id}{'SchedState'}$/, @allowed_batch_state) {
                    $any_error .= "\n" if $any_error;
                    $any_error .= PrbLocale::batch_state_error($lot_id, ${$batch_meta}{$lot_id}{'SchedState'}, @allowed_batch_state);
                } else {
                    $MES_ATTR{$lot_id} = ${$attr_ref}{$lot_id};
                    $MES_META{$lot_id} = ${$lot_meta}{$lot_id};
                    foreach my $prober (@selected_equipment) {
                        if (grep /$prober/, @{$lots{$lot_id}}) {
                            ${$germ_equip_index}{$prober}{$lot_id} = $mainframe_staged ? $TESTER_ID : $prober;
                            my $staged_to_equip = $child_staged ? $prober : $TESTER_ID;
                            foreach my $cassette (keys %{$LOAD_PORT{$prober}}) {
                                if (($LOAD_PORT{$prober}{$cassette}{'status'} eq 'available') and
                                     $LOAD_PORT{$prober}{$cassette}{'lot_id'} and
                                     ($LOAD_PORT{$prober}{$cassette}{'lot_id'} =~ $lot_id)) {
                                    $LOAD_PORT{$prober}{$cassette}{'batch_id'} = ${$batch_meta}{$lot_id}{'BatchId'};
                                    $LOAD_PORT{$prober}{$cassette}{'batch_type'} = ${$batch_meta}{$lot_id}{'BatchType'};
                                    $LOAD_PORT{$prober}{$cassette}{'batch_state'} = ${$batch_meta}{$lot_id}{'SchedState'};
                                    # knowing if the lot is staged to mainframe or chamber is needed when sending LotUpdate
                                    $LOAD_PORT{$prober}{$cassette}{'staged_to'} = $staged_to_equip;
                                }
                            }
                        } else {
                            notify('log', "Lot=$lot_id is staged to $prober but it is not being setup at this time");
                        }
                    }
                }
            }
        }
    }
    if ($warning and ($batch_found or !$OVERRIDE{'bsc_bypass'})) {
        # if at least one lot is staged, all lots must be staged
        # if we are in BSC mode and not bypassing BSC, all lots must be staged
        $any_error .= "\n" if $any_error;
        $any_error .= $warning;
    }
    return ($any_error, $batch_found, $recipe_param, $recipe_meta, $germ_equip_index);
}

###############################################################################
# Description:
#     get GeRM recipe information for any lot/card combination
# Returns:
#     nothing
# Globals:
#     $INSTRUCTIONS, %LOAD_PORT, %PCARD_DATA,
#     %GERM_LOT_INFO, %GERM_LOT_DETAIL, %GERM_EQUIP_PARAM, %GERM_EQUIP_META
#     @GERM_EXCEPTION_NAMES
###############################################################################
sub tk_get_recipe {
    push @FUNCTION_TRACE, "tk_get_recipe()";
    my $any_error;
    my ($status, $response);
    my ($equipParam, $equipMeta, $germLotDetail, $instructions);
    my %lots;       # hash used to avoid redundant calls for same lot/card
    (@GERM_EXCEPTION_NAMES) = ();  # initialize to empty
    foreach my $prober (keys %LOAD_PORT) {
        foreach my $cassette (keys %{$LOAD_PORT{$prober}}) {
            if (($LOAD_PORT{$prober}{$cassette}{'status'} eq 'available') and
                 $LOAD_PORT{$prober}{$cassette}{'lot_id'}) {
                # first hash key is lot_id, second hash key is card config
                my $card_config = $NO_PROBECARD ? 'none' : $PCARD_DATA{$prober}{'bit_config_id'};
                $lots{$LOAD_PORT{$prober}{$cassette}{'lot_id'}}{$card_config} = ();
            }
        }
    }
    notify('info', $PrbLocale::Msg{'calling_germ'});
    foreach my $lot_id (keys %lots) {
        foreach my $card_config (keys %{$lots{$lot_id}}) {
            ($status, $response, $equipParam, $equipMeta, $germLotDetail, $instructions) = get_germ_info($lot_id, $card_config);
            if ($status) {
                $any_error .= "\n" if $any_error;
                $any_error .= PrbLocale::germ_error($lot_id, $response);
            } elsif (${$equipMeta}{$TESTER_ID}{'recipe_hold_count'}) {
                $any_error .= "\n" if $any_error;
                $any_error .= PrbLocale::germ_recipe_hold($lot_id, $instructions);
            } else {
               # keep track of the type of GeRM recipe and the Exception names
               my @non_exception_xref_type;   # list of non-exception recipe types
               foreach my $equip_id (keys %{$equipParam}) {
                    if (${$equipMeta}{$equip_id}{'exception_name'}) {
                        push @GERM_EXCEPTION_NAMES, ${$equipMeta}{$equip_id}{'exception_name'};
                    } else {
                        push @non_exception_xref_type, ${$equipMeta}{$equip_id}{'recipe_xref_type'};
                    }
                }
                # for direct GeRM calls verify Engineering Deviations resolve to a GeRM exception
                if ($REQUEST and ($REQUEST ne 'DEBUG')) {
                    if (scalar @non_exception_xref_type) {
                        $any_error .= "\n" if $any_error;
                        # notice the localized exception name and the GeRM exception are both
                        # passed to make it easier to debug
                        $any_error .= PrbLocale::germ_recipe_not_an_exception($ENGR_REQUEST, $REQUEST);
                    }
                    # GeRM supports several operators with Input Variable exceptions
                    # I would like to restrict the check here to 'equal' and 'like' operators
                    # unfortunately complex exceptions by default may look like 'IV: = CORR and PT: = C2BBN9R1'
                    my $look_for = $REQUEST;  # same as the equal match below
                    my $pattern;
                    foreach my $exception (@GERM_EXCEPTION_NAMES) {
                        if (($pattern) = $exception =~ m/: like (.+)/) {
                            # the like portion must contain an '*', change to '.*'
                            $pattern =~ s/\*/\.\*/g;
                            $look_for = $pattern;
                        } elsif (($pattern) = $exception =~ m/IV: = ([^ ]+)/) {
                            $look_for = $pattern;
                        } elsif (($pattern) = $exception =~ m/: = (.+)/) {
                            $look_for = $pattern;
                        }
                        if ($REQUEST !~ /$look_for/) {
                            $any_error .= "\n" if $any_error;
                            $any_error .= PrbLocale::germ_no_matching_exception($exception, $REQUEST);
                        }
                    }
                }
                $GERM_LOT_INFO{$card_config}{$lot_id} = $response;
                $GERM_EQUIP_PARAM{$card_config}{$lot_id} = $equipParam;
                $GERM_EQUIP_META{$card_config}{$lot_id} = $equipMeta;
                $GERM_LOT_DETAIL{$card_config}{$lot_id} = $germLotDetail;
                $INSTRUCTIONS = $instructions;  # this needs work
            }
        }
    }
    if ($any_error) {
        notify('warn', $any_error);
    } else {
        notify('debug', Data::Dumper->Dump([\%GERM_LOT_INFO, \%GERM_EQUIP_PARAM, \%GERM_EQUIP_META, \%GERM_LOT_DETAIL, \$INSTRUCTIONS], [qw(*GERM_LOT_INFO *GERM_EQUIP_PARAM *GERM_EQUIP_META *GERM_LOT_DETAIL *INSTRUCTIONS)]));
        notify('info', '');
        tk_validate_recipe();
    }
}


###############################################################################
# Description:
#     verify recipe parameters are the same for all lots
# Returns:
#
# Globals:
#     $GERM_PROCESS, $GERM_RECIPE, $GERM_PID_EXPECTED,
#     $ALLOW_MIXED_REV_RECOVERY, $REPROBE_ALLOWED,
#     %LOAD_PORT, %GERM_EQUIP_PARAM, %GERM_EQUIP_META, %PROCESS, %RECIPE
###############################################################################
sub tk_validate_recipe {
    push @FUNCTION_TRACE, "tk_validate_recipe()";
    my $any_error;
    my $acceptable_card_warning;  # will be displayed if the wrong card is loaded
    my $germ_job_name;
    my $germ_temperature;
    my $germ_move_table;
    my $germ_pid;
    my $germ_allow_mixed_rev_recovery = 'no';
    my $germ_reprobe_allowed = 'yes'; # default is to allow reprobes
    my $temporary_germ_process;
    my $temporary_germ_recipe;
    my %lots;       # hash used to avoid redundant calls for same lot/card
    my %verify_params;
    my $parameter_set_count = 0;
    my %card_module_parameters;    # allow card specific parameter over-rides
    my %module_subrecipe_parameters; # to verify key card specific over-rides
    %RECIPE = (); # initialize
    my $card_id;
    foreach my $prober (keys %LOAD_PORT) {
        foreach my $cassette (keys %{$LOAD_PORT{$prober}}) {
            if (($LOAD_PORT{$prober}{$cassette}{'status'} eq 'available') and
                 $LOAD_PORT{$prober}{$cassette}{'lot_id'}) {
                # first hash key is lot_id, second hash key is card config
                my $card_config = $NO_PROBECARD ? 'none' : $PCARD_DATA{$prober}{'bit_config_id'};
                $lots{$LOAD_PORT{$prober}{$cassette}{'lot_id'}}{$card_config} = ();
                $card_id = $NO_PROBECARD ? 'none' : $PCARD_DATA{$prober}{'equip_id'}; #for (in/ex)clusion card id lists.
                if(!$NO_PROBECARD)
                {
                    $card_id =~ s/PC-//;
                    $card_id = int $card_id;
                }
            }
        }
    }
    # verify equipment parameters are the same for all lot/card configurations
    # when we start adding prober specific parameters or take advantage of
    # move tables tailored to a card configuration, this will need to change
    
    foreach my $lot_id (keys %lots) {
        foreach my $card_config (keys %{$lots{$lot_id}}) {
            my $exclude_card;
            my $include_card;
            my @acceptable_card_config;    # card types with assigned Test Job
            foreach my $equip_id (keys %{$GERM_EQUIP_PARAM{$card_config}{$lot_id}}) {
                foreach my $param_name (keys %{$GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}}) {
                    if (!$parameter_set_count) { # will evaluate true for first pass
                        $verify_params{$equip_id}{$param_name} = $GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name};
                        my $dump = Data::Dumper->new( [$GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name}], ['*value'])->Indent(0);
						if (!defined $PrbCfg::PlatformCfg{'GermVerbosity'} or !$PrbCfg::PlatformCfg{'GermVerbosity'}) {
	                        notify('debug', sprintf "GeRM: curr_config=%s param=%-15s %s", $card_config, $param_name, scalar $dump->Dump );
                        }
						else {
							notify($PrbCfg::PlatformCfg{'GermVerbosity'}, sprintf "GeRM: curr_config=%s param=%-15s %s", $card_config, $param_name, scalar $dump->Dump );
						}
                        
                        # hack
                        if ($param_name =~ /^Job[ _]Name$/i) {
                            $germ_job_name = $GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name};
                        } elsif ($param_name =~ /^MOVE_TABLE_NAME$/i) {
                            $germ_move_table = $GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name};
                        # Avezzano specifies TEMP instead of Temperature
                        } elsif ($param_name =~ /^Temp(erature)?$/i) {
                            $germ_temperature = $GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name};
                        } elsif ($param_name =~ /^PID$/i) {
                            $germ_pid = $GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name};
                        } elsif (($param_name =~ /^INTERRUPT_REV_UPDATE$/i) and $GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name} and
                                 ($GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name} =~ /yes/i) ) {
                            $germ_allow_mixed_rev_recovery = 'yes';
                        } elsif (($param_name =~ /^REPROBE_ALLOWED$/i) and $GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name}) {
                            if ($GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name} =~ /^[Nn]/) {
                                $germ_reprobe_allowed = 'no';
                            } elsif ($GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name} =~ /force/i) {
                                $germ_reprobe_allowed = 'force';
                            }
                        } elsif ($param_name =~ /^PROBE[ _]PROGRAM[ _]KEY$/i && $GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name}){
                           $GERM_PRB_LOT_ATTR{$lot_id}{'PROBE PROGRAM KEY'} = $GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name};
                        }
                    }
                    if (!defined $verify_params{$equip_id}{$param_name}) {
                            $any_error .= "\n" if $any_error;
                            $any_error .= PrbLocale::germ_param_undef($lot_id, $card_config, $equip_id, $param_name);
                    }
                    elsif (ref $verify_params{$equip_id}{$param_name}) 
                    {
                         if (($param_name =~ /^CARD_TYPE_(.+)$/i) and $GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name}{'CARD_CONFIG'}) 
                         {
                            if ($GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name}{'CARD_CONFIG'} eq $card_config) 
                            {
                                if ($GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name}{'INCLUSION_CARD_ID'})
                                {
                                    #we want to go through the include card if there is one in the card block
                                    my @card_list = split(',',$GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name}{'INCLUSION_CARD_ID'});
                                    foreach my $card (@card_list)
                                    {
                                        if ($card == $card_id)
                                        {
                                            #flag that the card on the tool is one in the list
                                            $include_card=1;
                                            notify('debug', "$card == $card_id" );
                                            last;
                                        }
                                    }
                                    if ($include_card)
                                    {
                                        #add the card parameters
                                        %card_module_parameters = %{$GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name}};
                                    }
                                    else
                                    {
                                        #set the error, card is not valid
                                        $any_error .= "\n" if $any_error;
                                        $any_error .= PrbLocale::card_inclusion($equip_id,$card_id,$GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name}{'INCLUSION_CARD_ID'});
                                    }
                                }
                                elsif ($GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name}{'EXCLUSION_CARD_ID'})
                                {
                                    #if no include section, but exclude section within the card block
                                    my @card_list = split(',',$GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name}{'EXCLUSION_CARD_ID'});
                                    foreach my $card (@card_list)
                                    {
                                        if ($card == $card_id)
                                        {
                                            $exclude_card = 1;
                                        }
                                    }
                                    #if card on the tool is not in the exclude list, then we can run
                                    if (!$exclude_card)
                                    {
                                        $include_card=1;
                                        %card_module_parameters = %{$GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name}};
                                    }
                                    else
                                    {
                                        #set the error, card is listed
                                        $any_error .= "\n" if $any_error;
                                        $any_error .= PrbLocale::card_exclusion($equip_id,$card_id,$GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name}{'EXCLUSION_CARD_ID'});
                                    }
                                }
                                else
                                {
                                    #if there is no include or exclude selection
                                    $include_card=1;
                                    %card_module_parameters = %{$GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name}};
                                }
                                notify('debug', Data::Dumper->Dump([\%card_module_parameters], [qw(*card_module_parameters)]));
                            } elsif ($GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name}{'CARD_CONFIG'}) {
                                # list of valid card types will be displayed if currently loaded card is incorrect
                                # changed to CARD_CONFIG from JOB_NAME.  This was not listing the acceptable 
                                # card error message if a job name was not specified in the card block, but the default   
                                # JOB_NAME was for all current configs. 
                                push @acceptable_card_config, $GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name}{'CARD_CONFIG'};
                            }
                        }
                    }
                }
                %RECIPE = %{$GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}};
            }
            if (scalar @acceptable_card_config ) {
                #means this recipe requires card, check compatability
                #if a Recipe will allow card to run, then it's set to 1
                #if a card is found in the exclude list, then set to zero
                #
                if((!$include_card or $exclude_card))
                {
                    $acceptable_card_warning .= "\n" if $acceptable_card_warning;
                    $acceptable_card_warning .= PrbLocale::card_not_compatible($lot_id, $card_config, @acceptable_card_config);
                }
                elsif(!keys %card_module_parameters and $card_id)
                {
                    #if the card module is not populated, and there is a card, then no compatible 
                    #configs were found
                    $acceptable_card_warning .= "\n" if $acceptable_card_warning;
                    $acceptable_card_warning .= PrbLocale::card_not_compatible($lot_id, $card_config, @acceptable_card_config);
                }
            }
            # the hash key indicating GeRM process may be 'ProcessName' or 'process' depending on if it was obtained
            # from Batch Stage Controller or from an m-msg sent to GeRM
            # GeRM recipe name may be useful, but is only available if it was obtained using m-msg (or in the LotStage message)
            foreach my $process_key ('ProcessName', 'process') {
                if ($GERM_EQUIP_META{$card_config}{$lot_id}{$TESTER_ID}{$process_key}) {
                    if (!$temporary_germ_process) {
                        $temporary_germ_process = $GERM_EQUIP_META{$card_config}{$lot_id}{$TESTER_ID}{$process_key};
                    } elsif ($temporary_germ_process ne $GERM_EQUIP_META{$card_config}{$lot_id}{$TESTER_ID}{$process_key}) {
                        $any_error .= "\n" if $any_error;
                        $any_error .= PrbLocale::germ_param_mismatch($process_key, $temporary_germ_process, $GERM_EQUIP_META{$card_config}{$lot_id}{$TESTER_ID}{$process_key});
                    }
                }
            }
            if ($GERM_EQUIP_META{$card_config}{$lot_id}{$TESTER_ID}{'recipe'}) {
                if (!$temporary_germ_recipe) {
                    $temporary_germ_recipe = $GERM_EQUIP_META{$card_config}{$lot_id}{$TESTER_ID}{'recipe'};
                } elsif ($temporary_germ_recipe ne $GERM_EQUIP_META{$card_config}{$lot_id}{$TESTER_ID}{'recipe'}) {
                    $any_error .= "\n" if $any_error;
                    $any_error .= PrbLocale::germ_param_mismatch('recipe', $temporary_germ_recipe, $GERM_EQUIP_META{$card_config}{$lot_id}{$TESTER_ID}{'recipe'});
                }
            }
            ++$parameter_set_count;
        }
    }
    if ($card_module_parameters{'JOB_NAME'}) {
        notify('debug', "GeRM JOB_NAME '$germ_job_name' over-written by card specific JOB_NAME '$card_module_parameters{'JOB_NAME'}'") if $germ_job_name;
        $germ_job_name = $card_module_parameters{'JOB_NAME'};
    }
    if ($card_module_parameters{'MOVE_TABLE_NAME'}) {
        notify('debug', "GeRM MOVE_TABLE_NAME '$germ_move_table' over-written by card specific MOVE_TABLE_NAME '$card_module_parameters{'MOVE_TABLE_NAME'}'") if $germ_move_table;
        $germ_move_table = $card_module_parameters{'MOVE_TABLE_NAME'};
    }
    if (!$germ_job_name or ($acceptable_card_warning and $card_id)) {
    #display an error if a job name is not found, or there is no warning message
    #yet there is a card_id
        $any_error .= "\n" if $any_error;
        if ($acceptable_card_warning) {
            $any_error .= $acceptable_card_warning;
        } else {
            $any_error .= $PrbLocale::Error{'germ_job_reqd'};
        }
    }
    unless ($OPT{'notemp'} or defined $germ_temperature) {
        $any_error .= "\n" if $any_error;
        $any_error .= $PrbLocale::Error{'germ_temp_reqd'};
    }
    if (defined $module_subrecipe_parameters{'JOB_NAME'}) {
        foreach my $test_job (@{$module_subrecipe_parameters{'JOB_NAME'}}) {
            if ($test_job ne $germ_job_name) {
                $any_error .= "\n" if $any_error;
                $any_error .= PrbLocale::germ_param_mismatch('JOB_NAME', $germ_job_name, $test_job);
            }
        }
    }
    if (defined $module_subrecipe_parameters{'MOVE_TABLE_NAME'}) {
        # move table name defaults to design ID if it is not defined in GeRM
        # this logic (definition of what is the move table name) is duplicated,
        # see tk_check_parameters
        my $step_table = $germ_move_table ? $germ_move_table : $DESIGN_ID;
        foreach my $move_table (@{$module_subrecipe_parameters{'MOVE_TABLE_NAME'}}) {
            if ($move_table ne $step_table) {
                $any_error .= "\n" if $any_error;
                $any_error .= PrbLocale::germ_param_mismatch('MOVE_TABLE_NAME', $step_table, $move_table);
            }
        }
    } elsif (($parameter_set_count > 1) and $card_module_parameters{'MOVE_TABLE_NAME'} and ($germ_move_table ne $DESIGN_ID)) {
        # more than one parameter set was encountered, indicating multiple lots and/or
        # multiple card configurations, a card specific move table was specified for one configuration
        # but not another.  We need to fail because one card specific move table over-ride
        # should not effect a different cards parameters
        # this is ugly! ugly! ugly!, and there is still a hole, Agghhh!
        $any_error .= "\n" if $any_error;
        $any_error .= PrbLocale::germ_param_mismatch('MOVE_TABLE_NAME', $germ_move_table, $DESIGN_ID);
    }
    if ($GERM_PID_EXPECTED) {
        if ($OPT{'offline'} and $OPT{'pid'} and !$germ_pid) {
            # hack to allow acameron to test TECH batches, because GeRM may not contain PID
            $germ_pid = $OPT{'pid'};
        }
        if (!$germ_pid) {
            # eventually GeRM should specify the Data Collection Process ID for
            # every step, it must specify it for some Tracking steps
            $any_error .= "\n" if $any_error;
            $any_error .= PrbLocale::germ_process_missing($STEP_NAME);
        } elsif (!lookup_tracking_step($germ_pid, $STEP_NAME)) {
            $any_error .= "\n" if $any_error;
            $any_error .= PrbLocale::germ_process_not_valid($germ_pid);
        } else {
            my $apparent_step = lookup_tracking_step($germ_pid, $STEP_NAME);
            if ($apparent_step) {
                configure_pid_selections($apparent_step, $germ_pid);   # for overriding the data collection mode
            }
            if ($PROCESS{'selected'} !~ /^$germ_pid /) {
                $PROCESS{'selected'} = $germ_pid;
                tk_pid_selected();
            }
        }
    }
    if (!$any_error) {
        $GERM_PROCESS = $temporary_germ_process;
        $GERM_RECIPE = $temporary_germ_recipe;
        $ALLOW_MIXED_REV_RECOVERY = $germ_allow_mixed_rev_recovery ? $germ_allow_mixed_rev_recovery : '';
        $REPROBE_ALLOWED = $germ_reprobe_allowed;
        notify('debug', sprintf "reprobe allowed:%s, allow_mixed_rev_recovery:%s, germ_allow_mixed_rev", $REPROBE_ALLOWED, $ALLOW_MIXED_REV_RECOVERY, $germ_allow_mixed_rev_recovery);        
        if ($GERM_PID_EXPECTED and $EQUIP_STATE_ALLOW{'mode_select'}) {
            # store in global hash, tk_check_parameters will be called after operator has a chance to edit mode
            $RECIPE{'job_name'} = $germ_job_name;
            $RECIPE{'Temperature'} = $germ_temperature if defined $germ_temperature;
            $RECIPE{'movetable'} = $germ_move_table if defined $germ_move_table;
            page_to('process_entry');
            if ($AUTO_START) {
                $W{'next'}->configure(-state => 'normal',);  # tk_configure_callback manages disable/enable
                $W{'next'}->invoke();
            }
        }
        else
        {
            #broke out the evaluation since it wasn't working right
            my ($status) = tk_check_parameters('germ', $germ_job_name, $germ_temperature, $PROCESS{'selected'}, $germ_move_table);
            if ($status)
            {
               $any_error .= "\n" if $any_error;
               $any_error .= $status;
           }
        }
    }
    if ($any_error) {
        notify('warn', $any_error);
    }
    return($any_error);
}

###############################################################################
# Description:
#     validates all questions have been answered in 'update' page if applicable
#     obtains new test job and/or move table if needed
#     parse move table
# Globals:
#     $LOCAL_OPERATION_MSG, $LOCAL_OPERATION_OK, $NEW_TEST_JOB_MSG,
#     $UPDATE_TEST_JOB, $NEW_MOVE_TABLE_MSG, $UPDATE_MOVE_TABLE,
#     $SCRAPPED_WAFERS, $PROBE_SCRAPPED, $LOCAL_JOB_PATH, $LOCAL_JOB_DIR,
#     $JOB_NAME, $LOCAL_MOVE_TABLE_DIR, $MOVE_TABLE, $ON_HOLD_WAFERS
#     $PROBE_ON_HOLD, $NEW_MOVE_TABLE_PATH, %EQUIP_STATE_ALLOW
###############################################################################
sub tk_confirm_settings {
    push @FUNCTION_TRACE, "tk_confirm_settings()";
    my $any_error;
    if (($NEW_MOVE_TABLE_MSG and !$UPDATE_MOVE_TABLE) or
        ($NEW_TEST_JOB_MSG and !$UPDATE_TEST_JOB) or
        ($LOCAL_OPERATION_MSG and !$LOCAL_OPERATION_OK) or
        ($ON_HOLD_WAFERS and !$PROBE_ON_HOLD) or
        ($SCRAPPED_WAFERS and !$PROBE_SCRAPPED)) {
        $any_error .= "\n" if $any_error;
        $any_error .= $PrbLocale::Error{'answer_required'};
    } elsif ($ON_HOLD_WAFERS and $PROBE_ON_HOLD and ($PROBE_ON_HOLD eq 'no')) {
        $any_error .= "\n" if $any_error;
        $any_error .= $PrbLocale::Error{'on_hold'};
    } elsif ($SCRAPPED_WAFERS and $PROBE_SCRAPPED and ($PROBE_SCRAPPED eq 'no')) {
        $any_error .= "\n" if $any_error;
        $any_error .= $PrbLocale::Error{'all_scrapped'};
    } elsif ($LOCAL_OPERATION_MSG and ($LOCAL_OPERATION_OK eq 'no')) {
        $any_error .= "\n" if $any_error;
        $any_error .= $PrbLocale::Error{'only_local_job'};
    } else {
        # check for LOCAL_JOB_DIR allows platforms like DNS that do not store jobs on the workstation
        # to bypass this job handling section
        if ($LOCAL_JOB_DIR) {
            $LOCAL_JOB_PATH = File::Spec->catfile($LOCAL_JOB_DIR, $JOB_NAME);

            # Download the previously used test job if this is a recovery scenario and GeRM
            # Test Job Rev Update is is set to no.            
            if($INTERRUPT_RECOVERY and $UPDATE_TEST_JOB =~ /no/i and $PREV_TEST_JOB_MSG) {
                notify('info', $PrbLocale::Msg{'downloading_job'});
                notify('log', "downloading_job $PREV_TEST_JOB_PATH job_name=$JOB_NAME");
                my $job_download_status = download_test_job($PREV_TEST_JOB_PATH, $LOCAL_JOB_PATH, $LOCAL_JOB_ARCHIVE_DIR);
                if ($job_download_status) {
                    $any_error .= "\n" if $any_error;
                    $any_error .= $job_download_status;
                }
            }
            # download test job if it is not available locally
            # or if a new version has been released
            # see get_clean_job for handling only the local archive is available and the uncompressed folder does not exist
            elsif (($NEW_TEST_JOB_MSG and ($UPDATE_TEST_JOB =~ /yes/i)) or ((!-d $LOCAL_JOB_PATH) and (!$LOCAL_OPERATION_MSG))) {
                notify('info', $PrbLocale::Msg{'downloading_job'});
                notify('log', "downloading_job  $NEW_TEST_JOB_PATH job_name=$JOB_NAME");
                my $job_download_status = download_test_job($NEW_TEST_JOB_PATH, $LOCAL_JOB_PATH, $LOCAL_JOB_ARCHIVE_DIR);
                if ($job_download_status) {
                    $any_error .= "\n" if $any_error;
                    $any_error .= $job_download_status;
                }
            }       
        }
        if (!$any_error and $LOCAL_MOVE_TABLE_DIR and !$NO_PROBECARD) {
            my $move_table_path = File::Spec->catfile($LOCAL_MOVE_TABLE_DIR, $MOVE_TABLE);
            my $copy_test_job_movetable;  # flag indicates a test job move table is available
            if ($OPT{'job_movetable'}) {
                $MOVE_TABLE_SERVER = File::Spec->catfile($LOCAL_JOB_PATH, 'move_tables');
                my $job_movetable = File::Spec->catfile($MOVE_TABLE_SERVER, $MOVE_TABLE);
                if (-f $job_movetable) {
                    # Note: there is a problem if get_clean_job is called and $OPT{'job_movetable'} is specified,
                    # because that would extract a fresh copy of the movetable to the job folder, but that copy
                    # may (but not likely) differ from the copy that is obtained the first time the job is
                    # downloaded, uncompressed, and parsed (in this function).
                    # To avoid that possibility I would have to reparse the move table after get_clean_job, and
                    # display errors.  TECH is the only site I know of that uses job_movetable, and they indicated
                    # that they did not allow local only operation, and I don't think they use $OPT{'cleanjob'}
                    # so this shouldn't be a big concern
                    $NEW_MOVE_TABLE_PATH = $job_movetable;
                    $copy_test_job_movetable = 1;
                }
            }
            # download move table if it is not available locally
            # or if a new version has been released
            if ($NEW_MOVE_TABLE_PATH and ($copy_test_job_movetable or (!-f $move_table_path) or ($NEW_MOVE_TABLE_MSG and ($UPDATE_MOVE_TABLE =~ /yes/i)))) {
                notify('info', $PrbLocale::Msg{'downloading_mt'});
                my $copy_status = copy_file($NEW_MOVE_TABLE_PATH, $move_table_path);
                if ($copy_status)  {
                    $any_error .= "\n" if $any_error;
                    $any_error .= $copy_status;
                }
            }
            if (!-f $move_table_path) {
                $any_error .= "\n" if $any_error;
                $any_error .= PrbLocale::move_table_not_available($MOVE_TABLE, $MOVE_TABLE_SERVER, $LOCAL_MOVE_TABLE_DIR);
            }
            if (!$any_error) {
                eval { # MTParser may throw an exception
                    my $mt_parse_status = parse_move_table($move_table_path);
                    if ($mt_parse_status) {
                        $any_error .= "\n" if $any_error;
                        $any_error .= $mt_parse_status;
                    }
                };
                if ($@) {
                    $any_error .= "\n" if $any_error;
                    $any_error .= PrbLocale::error_reading_move_table($move_table_path, 0, $@);
                }
            }
        }
        if (!$any_error) {
            # platform specific config file can perform last minute validation
            $any_error = PrbCfg::confirm_settings();
        }
    }
    if ($any_error) {
        notify('warn', $any_error);
        return $any_error;
    } else {
        page_to('job_info');
        if ($AUTO_START and (($INSTRUCTIONS and $OPT{'skip_instr_display'}) or !$INSTRUCTIONS) and !$EQUIP_STATE_ALLOW{'carrier'}) {
            # per sly if no operator involvement is needed, auto start the lot(s)
            # per Lehi, if skip_instruction option provided the  site doesn't want to wait for operator instructions to display
            $W{'next'}->configure(-state => 'normal',);  # tk_configure_callback manages disable/enable
            return($W{'next'}->invoke());
        } else {
            return(0);
        }
    }
}

###############################################################################
# Description:
#     prevents an engineering deviation from being selected when running
#     under a production step
# Returns:
#     nothing
# Globals:
#     $ENGR_REQUEST, %PROCESS, %W
###############################################################################
sub tk_pid_selected {
    my $browse_state = 'disabled';
    if ($OPT{'process_type'} and $EQUIP_STATE_ALLOW{'process_run'} and !$BSC_MODE) {
        # for 'deviation'
        $browse_state = 'readonly';
    } else {
        if (!$BSC_MODE) {
            # users can enter free form text or select from pre-defined options
            $browse_state = 'normal';
        }
        if ($PROCESS{'production'} and ($PROCESS{'production'} eq $PROCESS{'selected'})) {
            # don't allow Engineering Exceptions for Production Processes
            $ENGR_REQUEST = '';
        }
    }
    if ($W{'request_list'}) {
        $W{'request_list'}->configure(
            -state => $browse_state,
        );
    }
}

###############################################################################
# Description:
#     utility to add an option to a list widget
# Returns:
#     nothing
# Globals:
#     %W
###############################################################################
sub tk_add_option {
    # when called via the bind callback the first argument will be the widget
    # that method doesn't work as well if called directly, hence the need
    # to pass the $widget_key
    my ($not_used, $widget_key, $option_ref) = @_;
    # if user enters a custom deviation, add to deviation list
    if (! grep /^${$option_ref}$/, ($W{$widget_key}->choices)) {
        $W{$widget_key}->insert('end', ${$option_ref});
    }
    $W{'next'}->focus;
}

###############################################################################
# Description:
#     utility to manage options available in a list widget
# Returns:
#     nothing
# Globals:
#     $W
###############################################################################
sub tk_configure_options {
    my ($widget_key, @option_list) = @_;
    $W{$widget_key}->configure(
        -choices => \@option_list
    );
}

###############################################################################
# Description:
#     utility to manage options available to a widget
# Returns:
#     nothing
# Globals:
#     $W
###############################################################################
sub tk_widget_configure {
    my ($widget_key, $option_ref) = @_;
    $W{$widget_key}->configure(%{$option_ref});
}

###############################################################################
# Description:
#     validates over-ride parameters provided in 'override_entry' page
# Globals:
#     %OVERRIDE, $OVERRIDE_REASON
###############################################################################
sub tk_validate_override {
    my $any_error;
    if ($NO_OPERATOR_REQUIRED) { # except for override
        my $operator_validation_error = validate_operator();
        if ($operator_validation_error) {
            $any_error .= "\n" if $any_error;
            $any_error .= $operator_validation_error;
        }
    }
    unless ($OVERRIDE{'process'}) {
        $any_error .= "\n" if $any_error;
        $any_error .= $PrbLocale::Error{'process_required'};
    }
    unless ($OVERRIDE{'job_name'}) {
        $any_error .= "\n" if $any_error;
        $any_error .= $PrbLocale::Error{'job_required'};
    }
    unless ($OVERRIDE{'reason'}) {
        $any_error .= "\n" if $any_error;
        $any_error .= $PrbLocale::Error{'reason_required'};
    }
    foreach my $param_name (keys %{$PrbCfg::PlatformCfg{'RequiredParams'}}) {
        if (!defined $OVERRIDE{$param_name} or length($OVERRIDE{$param_name}) == 0) {
            $any_error .= "\n" if $any_error;
            $any_error .= PrbLocale::parameter_required($param_name);
        } elsif ($OVERRIDE{$param_name} !~ m/$PrbCfg::PlatformCfg{'RequiredParams'}{$param_name}/) {
            $any_error .= "\n" if $any_error;
            $any_error .= PrbLocale::parameter_format_error($param_name, $PrbCfg::PlatformCfg{'RequiredParams'}{$param_name});
        }
    }
    my $override_move_table = $OVERRIDE{'MOVE_TABLE_NAME'} if $OVERRIDE{'MOVE_TABLE_NAME'};
    if (!$any_error) {
        $OVERRIDE_REASON = $OVERRIDE{'reason'};
        if ($PrbLocale::OverrideReasons{$OVERRIDE{'reason'}}) {
            # use the hash value, the key is selected by operator (for localization)
            $OVERRIDE_REASON = $PrbLocale::OverrideReasons{$OVERRIDE{'reason'}};
        }
        my ($status) = tk_check_parameters('override', $OVERRIDE{'job_name'}, $OVERRIDE{'Temperature'}, $OVERRIDE{'process'}, $override_move_table);
        if ($status) {
            $any_error .= "\n" if $any_error;
            $any_error .= $status;
        }
    }
    if ($any_error) {
        notify('warn', $any_error);
    }
}

###############################################################################
# Description:
#     perform final checks before starting a new lot introduction
# Returns:
#     nothing
# Globals:
#     $LOCAL_JOB_DIR, $MAX_JOB_AGE_DAYS, $JOB_NAME, $INTERRUPT_RECOVERY,
#     $ALLOW_MIXED_REV_RECOVERY, %LOAD_PORT, %REQUIRE_CARRIER_VIEW
###############################################################################
sub tk_start_lot {
    time_it('tk_start_lot');
    my $status;
    my $eng_debug = (($REQUEST and ($REQUEST eq 'DEBUG')) or ($OVERRIDE_REASON and ($OVERRIDE_REASON eq 'DEBUG'))) ? 1 : 0;
    return if keys %REQUIRE_CARRIER_VIEW;
    if ( $OPT{'skip_instr_display'}  && $INSTRUCTIONS ) {
       for ( my $i=0; $i<400; $i++ ) {  # Pause for 4 seconds to allow user to cancel/see operator instructions
         $W{'main'}->update();
         $W{'main'}->after(10);
       }
    }
    if ($status = PrbCfg::pre_start_check()) {
        notify('warn', $status);
    } elsif (($OPT{'cleanjob'} or ($LOCAL_JOB_DIR and (!-d $LOCAL_JOB_PATH) and $LOCAL_OPERATION_MSG and ($LOCAL_OPERATION_OK =~ /yes/i))) and ($status = get_clean_job($JOB_NAME, $LOCAL_JOB_PATH, $LOCAL_JOB_ARCHIVE_DIR))) {
        notify('warn', $status);
    } elsif ($INTERRUPT_RECOVERY and $ALLOW_MIXED_REV_RECOVERY and ($ALLOW_MIXED_REV_RECOVERY =~ /no/i) and ( $status = check_test_job_revision() ) ) {
        notify('warn', $status);
    } elsif ($status = write_attributes_and_dlog_header()) {
        notify('warn', $status);
    } elsif ($status = commit_batches($eng_debug)) {
        notify('warn', $status);
    } elsif ($status = PrbCfg::start_lot_processing()) {
        notify('warn', $status);
    } else {
        time_it('tk_start_lot', 'end');
        record_setup_information();
        if ($LOCAL_JOB_DIR and $JOB_NAME) {
            my (@jobs_removed) = cleanup_old_directories($LOCAL_JOB_DIR, $MAX_JOB_AGE_DAYS, $JOB_NAME);
            # this was added to remove job archives as the uncompressed directory is removed
            cleanup_old_archives($LOCAL_JOB_ARCHIVE_DIR, @jobs_removed);
        }
        my @all_current_lots;  # includes active and available
        foreach my $prober (keys %LOAD_PORT) {
            foreach my $cassette (keys %{$LOAD_PORT{$prober}}) {
                if ($LOAD_PORT{$prober}{$cassette}{'lot_id'}) {
                    push @all_current_lots, $LOAD_PORT{$prober}{$cassette}{'lot_id'};
                }
            }
        }
        unless ($PrbCfg::PlatformCfg{'SkipAttrLotID'} and ($PrbCfg::PlatformCfg{'SkipAttrLotID'} =~ m/yes/i)) {
            cleanup_old_directories($PrbCfg::PlatformCfg{'AttrDir'}, $PrbCfg::PlatformCfg{'MaxAttrAge'}, @all_current_lots);
        }
        cleanup_orphaned_batches(@all_current_lots) unless($OPT{'no_batch_clean'});;
        post_start_actions();
        cleanup();
    }
}

###############################################################################
# Description:
#     called when user selects Cancel button, logs failures if applicable
# Returns:
#     nothing
# Globals:
#     %W
###############################################################################
sub tk_cancel {
    my $status_info = $W{'status'}->get('1.0', 'end');
    chomp($status_info);
    if ($status_info) {
        $status_info =~ s/\n/;/g;
        record_setup_information($status_info);
    }
    cleanup();
}

###############################################################################
# Description:
#     validates quantity of wafers to trend
# Returns:
#     true or false if entered value is OK, response is understood by Tk
#     entry widget
# Globals:
#     %LOAD_PORT
###############################################################################
sub tk_validate_quantity {
    my ($prober, $cassette, $value) = @_;
    return(!$value or (( $value =~ /^\d+$/ ) and ($value <= $LOAD_PORT{$prober}{$cassette}{'quantity'})));
}

###############################################################################
# Description:
#     displays the carrier with wafers selected for processing
# Returns:
# Globals:
#     $REPROBE_ALLOWED, %W, %LOAD_PORT, %CARRIER_USER_COPY, %REQUIRE_CARRIER_VIEW
###############################################################################
sub tk_display_carrier {
    # need to obtain the wafers selected from processing using qcdm
    # this need work
    my ($prober, $cassette, $value) = @_;
    my $lot_id = $LOAD_PORT{$prober}{$cassette}{'lot_id'};
    if ($lot_id) {
        delete $REQUIRE_CARRIER_VIEW{$lot_id};
        my %carrier_definition;
        my $view_only = $EQUIP_STATE_ALLOW{'carrier'} ? 0 : 1;
        my $ok_label = $PrbLocale::Msg{'ok'};
        # create a deep copy to allow user to edit and click cancel without saving changes
        foreach my $slot_num (keys %{$CARRIER_USER_COPY{$prober}{$cassette}}) {
            foreach my $carrier_item (keys %{$CARRIER_USER_COPY{$prober}{$cassette}{$slot_num}}) {
                $carrier_definition{$slot_num}{$carrier_item} = $CARRIER_USER_COPY{$prober}{$cassette}{$slot_num}{$carrier_item};
            }
        }
        my @protected_states = ('DataRework', 'Processed'); # CQ-ISTRK02870270
        if (!$OVERRIDE{'requested'} and ( ($REPROBE_ALLOWED eq 'no') or $INTERRUPT_RECOVERY)) {
            notify('debug', "Setting DataComplete|DataAborted to protected states - Recovery: $INTERRUPT_RECOVERY" );
            push @protected_states, 'DataComplete';
            push @protected_states, 'DataAborted';
        }
        my $answer = $W{'carrier'}->Show(
            -carrier    => \%carrier_definition,
            -order      => 'descending',
            -viewonly   => $view_only,
            -lok        => $ok_label,
            -protected  => \@protected_states,
        );
        if ($answer eq 'Ok') {
            my (%carrier) = $W{'carrier'}->cget('carrier');
            foreach my $slot_num (keys %{$CARRIER_USER_COPY{$prober}{$cassette}}) {
                # the SlotSelect super widget removes 'WaferState' if -unassigned is an empty string
                $carrier{$slot_num}{'WaferState'} = $UNASSIGNED_SLOT unless ($carrier{$slot_num}{'WaferState'});
            }
            # overwrite the user's copy of the carrier map
            %{$CARRIER_USER_COPY{$prober}{$cassette}} = %carrier;
            update_wafer_counts();
        }
        $W{'carrier'}->Hide();
    }
}

###############################################################################
# Description:
#     validates a data entry field contains only digits
# Returns:
#     true or false if entered value is OK, response is understood by Tk
#     entry widget
# Globals:
#     none
###############################################################################
sub tk_validate_numeric {
    my ($value) = @_;
    return(!$value or ( $value =~ /^\d+$/ ));
}

###############################################################################
# Description:
#     callback for checkbutton changes
# Returns:
#     nothing
# Globals:
#     %W, %OVERRIDE
###############################################################################
sub tk_override_button_callback {
    if ($OVERRIDE{'requested'}) {
        if ($W{'bsc_bypass'} and $EQUIP_STATE_ALLOW{'bsc_bypass'}) {
            $W{'bsc_bypass'}->select();
            $W{'bsc_bypass'}->configure(-state => 'disabled',);
        }
    } else {
        if ($W{'bsc_bypass'} and $EQUIP_STATE_ALLOW{'bsc_bypass'}) {
            $W{'bsc_bypass'}->deselect();
            $W{'bsc_bypass'}->configure(-state => 'normal',);
        }
    }
}

###############################################################################
# Description:
#     used to copy LotIDs when a lot is split between heads
# Returns:
#     nothing
# Globals:
#     %OPT, %LOAD_PORT
###############################################################################
sub copy_lot_info {
    my ($source) = @_;
    my ($destination);

    foreach my $prober (sort keys %LOAD_PORT) {
        if ($source ne $prober) {
            $destination = $prober;
        }
    }
    $LOAD_PORT{$destination}{'front'}{'lot_id'} = $LOAD_PORT{$source}{'front'}{'lot_id'};
    if ($OPT{'dual'}) {
        $LOAD_PORT{$destination}{'rear'}{'lot_id'} = $LOAD_PORT{$source}{'rear'}{'lot_id'};
    }
}

###############################################################################
# Description:
#     called when user selects Next or Previous to change pages
# Returns:
#     nothing
# Globals:
#     $NEW_MOVE_TABLE_MSG, $UPDATE_MOVE_TABLE, $NEW_TEST_JOB_MSG,
#     $UPDATE_TEST_JOB, $NEXT_SCREEN_LABEL, $LOCAL_OPERATION_MSG,
#     $SCRAPPED_WAFERS, $ENGR_REQUEST, $DEVIATION_LABEL, $INSTRUCTIONS
#     $GERM_PID_EXPECTED, $ON_HOLD_WAFERS, %LOAD_PORT, %OVERRIDE, %W
#     %REQUIRE_CARRIER_VIEW
###############################################################################
sub page_to {
    my ($destination_page) = @_;
    push @FUNCTION_TRACE, "page_to($destination_page)";
    $W{'status'}->delete('1.0', 'end');
    $W{'status'}->configure(
        -background => $W{'default_bg'},
        -foreground => $W{'default_fg'},
    );
    # unpack the frames that are currently being displayed
    if (!defined $W{'current'}) {
        # do nothing
    } elsif ($W{'current'} eq 'oper_entry') {
        $W{'oper_entry'}->packForget();
        $W{'lot_entry'}->packForget();
    } elsif ($W{'current'} eq 'process_entry') {
        $W{'process_entry'}->packForget();
        $W{'lot_info'}->packForget();
    } elsif ($W{'current'} eq 'override_entry') {
        $W{'override_entry'}->packForget();
        $W{'lot_info'}->packForget();
    } elsif ($W{'current'} eq 'update') {
        $W{'update'}->packForget();
        $W{'lot_info'}->packForget();
    } elsif ($W{'current'} eq 'job_info') {
        $W{'job_info'}->packForget();
        $W{'lot_info'}->packForget();
    }
    # previous page button is disabled if we are displaying the first page
    if ($destination_page ne 'oper_entry') {
        $W{'previous'}->configure(
            -state => 'normal',
        );
    } else {
        $W{'previous'}->configure(
            -state => 'disabled',
        );
    }
    # text displayed for next button changes when we get to the last screen
    if ($destination_page eq 'job_info') {
        $NEXT_SCREEN_LABEL = $PrbLocale::Msg{'start'};
    } else {
        $NEXT_SCREEN_LABEL = $PrbLocale::Msg{'next'};
    }
    if ($destination_page eq 'oper_entry') {
        # attempt to manage 'request_list' state correctly when user navigates using 'previous'
        $BSC_MODE = undef;
        $PROCESS{'selected'} = '';
        tk_pid_selected();
        tk_configure_callback('next', \&tk_validate_lots);
    } elsif ($destination_page eq 'process_entry') {
        $W{'previous'}->configure(
            -command => [ \&page_to, 'oper_entry' ],
        );
        if ($GERM_PID_EXPECTED and $EQUIP_STATE_ALLOW{'mode_select'}) {
            tk_configure_callback('next', \&tk_check_process_id);
        } else {
            tk_configure_callback('next', \&tk_get_recipe);
        }
        # remove focus from data entry fields so keyboard input is not gobbled up
        # this was allowing LotIDs to be changed in the step_page
        $W{'next'}->focus;
    } elsif ($destination_page eq 'override_entry') {
        $W{'previous'}->configure(
            -command => [ \&page_to, 'oper_entry' ],
        );
        tk_configure_callback('next', \&tk_validate_override);
        # remove focus from data entry fields so keyboard input is not gobbled up
        # this was allowing LotIDs to be changed in the step_page
        $W{'next'}->focus;
    } elsif ($destination_page eq 'update') {
        if ($OVERRIDE{'requested'}) {
            $W{'previous'}->configure(
                -command => [ \&page_to, 'override_entry' ],
            );
        } elsif ($GERM_PID_EXPECTED and !$EQUIP_STATE_ALLOW{'mode_select'}) {
            $W{'previous'}->configure(
                -command => [ \&page_to, 'oper_entry' ],
            );
        } else {
            $W{'previous'}->configure(
                -command => [ \&page_to, 'process_entry' ],
            );
        }
        tk_configure_callback('next', \&tk_confirm_settings);
    } elsif ($destination_page eq 'job_info') {
        # we can get to this page via multiple routes
        if (($NEW_MOVE_TABLE_MSG and ($UPDATE_MOVE_TABLE =~ /no/i)) or ($NEW_TEST_JOB_MSG and ($UPDATE_TEST_JOB =~ /no/i))) {
            $W{'previous'}->configure(
                -command => [ \&page_to, $W{'current'} ],
            );
        } elsif ($OVERRIDE{'requested'}) {
            $W{'previous'}->configure(
                -command => [ \&page_to, 'override_entry' ],
            );
        } elsif ($GERM_PID_EXPECTED and !$EQUIP_STATE_ALLOW{'mode_select'}) {
            $W{'previous'}->configure(
                -command => [ \&page_to, 'oper_entry' ],
            );
        } else {
            $W{'previous'}->configure(
                -command => [ \&page_to, 'process_entry' ],
            );
        }
        tk_configure_callback('next', \&tk_start_lot);
    }
    if ($destination_page eq 'oper_entry') {
        $W{'oper_entry'}->pack(-fill => 'both',);
        $W{'lot_entry'}->pack(-fill => 'both',);
        # check if a setup is allowed
        my $available_load_port = 0;
        foreach my $prober (keys %LOAD_PORT) {
            foreach my $cassette (keys %{$LOAD_PORT{$prober}}) {
                if ($LOAD_PORT{$prober}{$cassette}{'status'} eq 'available') {
                    $available_load_port = 1;
                }
            }
        }
        unless ($available_load_port) {
            notify('warn', $PrbLocale::Error{'no_load_ports'});
        }
    } elsif ($destination_page eq 'process_entry') {
        $W{'process_entry'}->pack(-fill => 'both',);
        $W{'lot_info'}->pack(-fill => 'both',);
    } elsif ($destination_page eq 'override_entry') {
        $W{'override_entry'}->pack(-fill => 'both',);
        $W{'lot_info'}->pack(-fill => 'both',);
    } elsif ($destination_page eq 'update') {
        # use local Test Job
        if ($LOCAL_OPERATION_MSG) {
            $W{'local_operation'}->pack(
                -side => 'right',
                -padx => 10,
                -pady => 10,
            );
        } else {
            $W{'local_operation'}->packForget();
        }
        # update Test Job
        if ($NEW_TEST_JOB_MSG) {
            $W{'update_job'}->pack(
                -side => 'right',
                -padx => 10,
                -pady => 10,
            );
        } else {
            $W{'update_job'}->packForget();
        }
        # update Move Table
        if ($NEW_MOVE_TABLE_MSG) {
            $W{'update_move_table'}->pack(
                -side => 'right',
                -padx => 10,
                -pady => 10,
            );
        } else {
            $W{'update_move_table'}->packForget();
        }
        # probe on-hold wafers
        if ($ON_HOLD_WAFERS) {
            $W{'probe_on_hold'}->pack(
                -side => 'right',
                -padx => 10,
                -pady => 10,
            );
        } else {
            $W{'probe_on_hold'}->packForget();
        }
        # allow scrapped wafers
        if ($SCRAPPED_WAFERS) {
            $W{'probe_scrapped'}->pack(
                -side => 'right',
                -padx => 10,
                -pady => 10,
            );
        } else {
            $W{'probe_scrapped'}->packForget();
        }
        $W{'update'}->pack(-fill => 'both',);
        $W{'lot_info'}->pack(-fill => 'both',);
    } elsif ($destination_page eq 'job_info') {
        if ($ENGR_REQUEST) {
            $DEVIATION_LABEL = $PrbLocale::Msg{'deviation_type'};
        } else {
            $DEVIATION_LABEL = '';
        }
        my $special_instructions;
        if ($OVERRIDE{'requested'}) {
            $special_instructions .= "\n" if $special_instructions;
            $special_instructions .= $PrbLocale::Msg{'verify_wafers'};
            %REQUIRE_CARRIER_VIEW = ();
            foreach my $prober (keys %LOAD_PORT) {
                foreach my $cassette (keys %{$LOAD_PORT{$prober}}) {
                    if (($LOAD_PORT{$prober}{$cassette}{'status'} eq 'available') and
                         $LOAD_PORT{$prober}{$cassette}{'lot_id'}) {
                        $REQUIRE_CARRIER_VIEW{$LOAD_PORT{$prober}{$cassette}{'lot_id'}} = ();
                    }
                }
            }
        }
        if ($INSTRUCTIONS) {
            $special_instructions .= "\n" if $special_instructions;
            $special_instructions .= $INSTRUCTIONS;
        }
        if ($special_instructions) {
            notify('info', $special_instructions);
        }
        $W{'job_info'}->pack(-fill => 'both',);
        $W{'lot_info'}->pack(-fill => 'both',);
    }
    $W{'current'} = $destination_page;
}


###############################################################################
# Description:
#     obtains the Probe Lot, Wafer, Process, and Part information.
#     Data is returned in Globals since it will be used in
#     various Tk widget callbacks.
#
#     Start Lot Key and scrapped wafer checks previously contained in
#     get_probe_lot_and_wafer_attributes has been added here
#
#     The first 4 characters of the waferIDs (assigned when lots are started in
#     the fab) are supposed to match the last 4 characters of the Start Lot Key.
#     This data integrity is used to lookup process data in the event of a
#     customer return.  drace, rschaeffer, sly, pprew, mcunliffe, et.al.
#     agreed to require this check, and only allow deviations if a
#     Lot Attribute 'UNMATCHED SLK' is set to 'YES'
#
# Returns:
#     $error - undef for success, localized error for failure
# Globals:
#     $SCRAPPED_WAFERS, %EQUIP_STATE_ALLOW,
#     %PRB_LOT_ATTR, %PRB_WFR_ATTR, %PRB_WFR_META, %PRB_PROCESS_ATTR
#     %PRB_PART_ATTR
###############################################################################
sub get_probe_lot_wafer_process_data {
    my ($lot_id, $pid) = @_;
    time_it('get_probe_lot_wafer_process_data');
    my $any_error;
    my ($status, $reply) = GetProcessDataPackage($OPT{'site'}, $lot_id, $pid, undef, @{$SITE_CFG{'PrbTrack'}{$OPT{'site'}}});
    if ($status) {
        $any_error = PrbLocale::ptrack_error($lot_id, $status);
    }
    else {
        my ($parse_status, $probe_lot_attr, $probe_wafer_attr, $process_attr, $reticle_data, $part_attributes, $part_definition, $scribe_table) = parse_probe_process_data($reply);
        if ($parse_status) {
            # error is already localized
            $any_error = $parse_status;
        } else {
            my %wafer_id_integrity; # hash used to check wafer ID matches Start Lot Key
            my $warning_message;
            my $valid_wafer_found = 0;
            my @scrapped_wafers;
            my (@wafer_status_filter) = @ProbeTrackInterface::WAFER_FILTER;
            # Menu 2.0 did not allow scrapped wafers to be probed except for
            # non-production setups, and then only after obtaining confirmation
            # wafers that did not match IN_LOT or SCRAPPED were removed from hashes
            foreach my $wafer_id (keys %{$probe_wafer_attr}) {
                if (grep /${$probe_wafer_attr}{$wafer_id}{'WAFER_STATUS'}/, @wafer_status_filter) {
                    $valid_wafer_found = 1;
                } elsif (${$probe_wafer_attr}{$wafer_id}{'WAFER_STATUS'} =~ /SCRAPPED/) {
                    push @scrapped_wafers, $wafer_id;
                }
                if (substr(${$probe_wafer_attr}{$wafer_id}{'START LOT KEY'}, 3, 4) ne substr($wafer_id, 0, 4)) {
                    push @{$wafer_id_integrity{${$probe_wafer_attr}{$wafer_id}{'START LOT KEY'}}}, $wafer_id;
                    $warning_message .= "${$probe_wafer_attr}{$wafer_id}{'START LOT KEY'}:$wafer_id ";
                }
            }
            if (!$valid_wafer_found) {
                if ($EQUIP_STATE_ALLOW{'scrapped'}) {
                    push @wafer_status_filter, 'SCRAPPED';
                    if (!scalar @scrapped_wafers) {
                        $any_error .= "\n" if $any_error;
                        $any_error .= PrbLocale::no_wafers($lot_id, @wafer_status_filter);
                    } else {
                        $SCRAPPED_WAFERS .= "\n" if $SCRAPPED_WAFERS;
                        $SCRAPPED_WAFERS .= PrbLocale::continue_with_scrapped_wafers($lot_id);
                    }
                } else {
                    $any_error .= "\n" if $any_error;
                    $any_error .= PrbLocale::no_wafers($lot_id, @wafer_status_filter);
                }
            }
            # remove wafers that have an incorrect WAFER_STATUS
            # see ProbeTrackInterface::set_attribute_hash
            foreach my $wafer_id (keys %{$probe_wafer_attr}) {
                my $wafer_status = ${$probe_wafer_attr}{$wafer_id}{'WAFER_STATUS'};
                if (!grep /$wafer_status/, @wafer_status_filter) {
                    notify('log', "removing Lot=$lot_id Wafer=$wafer_id, because status=$wafer_status");
                    delete ${$probe_wafer_attr}{$wafer_id};
                    # MES wafer level tracking is not enabled in 200mm factories.
                    # The MES CarrierMap is populated at Probe login, but some Probe wafer level changes are not
                    # synchronized with MES.  This issue is being addressed by Probe IS team, but mismatches may
                    # require manual intervention (i.e. Lot Check).  MIT would like to automatically reconcile
                    # scrapped wafer issues.  Other sites may also do this by enabling the -carrier_fix option.
                    if ($OPT{'carrier_fix'}) {
                        foreach my $slot_num (keys %{$MES_META{$lot_id}{'CarrierSlotList'}}) {
                            if (${$scribe_table}{$wafer_id} and ($MES_META{$lot_id}{'CarrierSlotList'}{$slot_num}{'WaferScribe'} eq ${$scribe_table}{$wafer_id}{'SCRIBE'})) {
                                notify('log', "removing MES CarrierSlotList for Wafer=$wafer_id in Slot=$slot_num, because status=$wafer_status");
                                delete $MES_META{$lot_id}{'CarrierSlotList'}{$slot_num};
                            }
                        }
                    }
                    delete ${$scribe_table}{$wafer_id} if defined ${$scribe_table}{$wafer_id};
                    # originally I ignored the PRB_PROCESS_ATTR removal because of the more complicated indexing
                    # however, that caused issues with interrupt recovery trying to reprobe wafers that were scrapped
                    # it is probably easiest to perform the removal here, rather than complicating interrupt recovery
                    foreach my $run_id (keys %{${$process_attr}{$pid}}) {
                        if (${$process_attr}{$pid}{$run_id}{$wafer_id}) {
                            delete ${$process_attr}{$pid}{$run_id}{$wafer_id};
                            notify('log', "removing Process Attributes for Wafer=$wafer_id at Process=$pid Run=$run_id, because status=$wafer_status");
                        }
                    }
                    delete ${$reticle_data}{$wafer_id} if defined ${$reticle_data}{$wafer_id};
                }
            }
            if (scalar keys %wafer_id_integrity) {
                if (defined ${$probe_lot_attr}{$lot_id}{'UNMATCHED SLK'} and (${$probe_lot_attr}{$lot_id}{'UNMATCHED SLK'} eq 'YES')) {
                    notify('log', "WARNING Lot '$lot_id' has Attribute 'UNMATCHED SLK' set to YES, mismatch=$warning_message");
                } else {
                    $any_error .= "\n" if $any_error;
                    $any_error .= PrbLocale::wafer_id_slk_mismatch($lot_id, %wafer_id_integrity);
                }
            }
            $PRB_LOT_ATTR{$lot_id} = $probe_lot_attr;
            $PRB_WFR_ATTR{$lot_id} = $probe_wafer_attr;
            $PRB_WFR_META{$lot_id} = $scribe_table;
            $PRB_PROCESS_ATTR{$lot_id} = $process_attr;
            $PRB_RETICLE_HISTORY{$lot_id} = $reticle_data;
            $PRB_PART_ATTR{$lot_id} = $part_attributes;
        }
    }
    # replace probe lot attributes with GeRM overrides
    foreach my $attr_id(keys %{$GERM_PRB_LOT_ATTR{$lot_id}}){
      notify('debug',"$attr_id value '$PRB_LOT_ATTR{$lot_id}{$lot_id}{$attr_id}' for $lot_id over-written by GeRM PROBE_PROGRAM_KEY value '$GERM_PRB_LOT_ATTR{$lot_id}{$attr_id}'");
      $PRB_LOT_ATTR{$lot_id}{$lot_id}{$attr_id} = $GERM_PRB_LOT_ATTR{$lot_id}{$attr_id}; 
    }
    time_it('get_probe_lot_wafer_process_data', 'end');
    return($any_error);
}

###############################################################################
# Description:
#     obtains the Probe Data Collection IDs previously obtained through an
#     http request.  Data is returned in Globals since it will be used in
#     various Tk widget callbacks.
# Returns:
#     nothing for success or localized error
# Globals:
#
###############################################################################
sub get_probe_process_IDs {
    time_it('get_probe_process_IDs');
    my $operation_code;
    if ($OPT{'group_name'} =~ /FUNCT/i) {
        $operation_code = "P,B";
    } elsif ($OPT{'group_name'} =~ /PARAM/i) {
        $operation_code = "R,M";
    } elsif ($OPT{'group_name'} =~ /CLEAN/i) {
        $operation_code = "C";
    } elsif ($OPT{'group_name'} =~ /LASER/i) {
        $operation_code = "L";
    } elsif ($OPT{'group_name'} =~ /BAKE/i) {
        $operation_code = "W";
    } elsif ($OPT{'group_name'}) {
        $operation_code = $OPT{'group_name'};
    }
    my ($status, $reply) = GetProcessDefinition($OPT{'site'}, $operation_code, @{$SITE_CFG{'PrbTrack'}{$OPT{'site'}}});
    if ($status) {
        fatal_startup_error(PrbLocale::probe_process_definition_error($status));
    }
    else {
        my ($parse_status, undef, undef, undef, undef, undef, $part_definition, undef) = parse_probe_process_data($reply);
        if ($parse_status) {
            # error is already localized
            fatal_startup_error($parse_status);
        } else {
            configure_process_list($part_definition);
        }
    }
    time_it('get_probe_process_IDs', 'end');
}

###############################################################################
# Description:
#     parse the XML response to Probe Tracking GetProcessDataPackage
#     and return Perl hashes
#
#     Note: ignores possibility of duplicate wafer-id and scribe associations
# Returns:
#     $error                   - undef for success, Localized error for fail
#     \%LotAttributes          - Probe Lot Attribute hash
#     \%WaferAttributes        - Probe Wafer Attribute hash
#     \%ProcessAttributes      - Probe Process Attributes
#     \%ProcessState           - Probe Process State
#     \%ReticleData            - Wafer Reticle History
#     \%PartAttributes         - Part Attributes
#     \%ProcessDefinitionData  - Probe Data Collection Definition
#     \%scribe_table           - Wafer Scribe Table
# Globals:
#
###############################################################################
sub parse_probe_process_data {
    my ($xml_data) = @_;
    my (%probe_data, %element_attributes, %scribe_table);
    my ($probe_data_section, $wafer_id, $wafer_scribe, $process_id, $run_id);
    my ($lot_id, $exception, $soap_fault, $any_error);
    eval {
        my $xp = XML::Parser->new(
            Style     => 'Stream',
            Handlers  => {
                Char  => sub {
                    my ($expat, $string) = @_;
                    if ($probe_data_section) {
                        if ($expat->current_element =~ m/^AttributeValue$/) {
                            if ($process_id) {
                                $probe_data{$probe_data_section}{$process_id}{$run_id}{$wafer_id}{$element_attributes{'Name'}} = $string;
                            } elsif ($wafer_id) {
                                $probe_data{$probe_data_section}{$wafer_id}{$element_attributes{'Name'}} = $string;
                            } elsif ($probe_data_section =~ m/^LotAttributes$/) {
                                # Lot Attributes should have a lot_id hash key (like wafer_id) for backward compatibility
                                $probe_data{$probe_data_section}{$lot_id}{$element_attributes{'Name'}} = $string;
                            } else {
                                $probe_data{$probe_data_section}{$element_attributes{'Name'}} = $string;
                            }
                        } elsif ($probe_data_section =~ m/^ProcessDefinitionData$/) {
                            $probe_data{$probe_data_section}{$process_id}{$expat->current_element} = $string;
                        } elsif ($probe_data_section =~ m/^ProcessState$/) {
                            $probe_data{$probe_data_section}{$process_id}{$run_id}{$wafer_id} = $string;
                        } elsif ($probe_data_section =~ m/^ReticleData$/) {
                            push @{$probe_data{$probe_data_section}{$wafer_id}{$expat->current_element}}, $string;
                        }
                    } elsif ($exception) {
                        # there may be ways to handle localized errors if we read the LanguageId
                        # then only look for that section, Example:
                        # <ExceptionSection>
                        #    <LanguageId>English</LanguageId>
                        #    <ExceptionList>
                        #      <Exception ErrorCode="3501" CategoryName="PRODUCT TRACKING">
                        # .
                        # .
                        #        <EnglishSection>
                        #          <ErrorText>Invalid process filter list.  At least one process filter must be specified.</ErrorText>
                        #          <DetailTextList/>
                        #        </EnglishSection>
                        if ($expat->current_element =~ /Text$/) {
                            $any_error .= "\n" if $any_error;
                            $any_error .= $string;
                        }
                    } elsif ($soap_fault) {
                        if ($expat->current_element =~ /detail/i) {
                            $any_error .= "\n" if $any_error;
                            $any_error .= $string;
                        }
                    } elsif ($expat->current_element =~ m/^LotId$/) {
                        $lot_id = $string;
                    }
                },
                Start => sub {
                    my ($expat, $element, %attrs) = @_;
                    if ($element =~ m/^ProbeDataSection$/) {
                        $probe_data_section = $attrs{'Name'};
                    } elsif ($element =~ m/^Wafer$/) {
                        $wafer_id = $attrs{'WaferId'};
                        $wafer_scribe = $attrs{'WaferScribeId'};
                        $scribe_table{$wafer_id}{'SCRIBE'} = $wafer_scribe;
                    } elsif ($element =~ m/^Process$/) {
                        $process_id = $attrs{'ProcessId'};
                        $run_id = $attrs{'RunId'} if $attrs{'RunId'};
                    } elsif (($element =~ m/^Reticle$/) and ($probe_data_section =~ m/^ReticleData$/)) {
                        # LevelName is the only reliable key distinguishing reticle level
                        # for assembly returns, because FabStepName is not accurate
                        push @{$probe_data{$probe_data_section}{$wafer_id}{'LevelName'}}, $attrs{'LevelName'};
                    } elsif ($element =~ m/^ExceptionSection$/) {
                        # Tracking Server uses this element to display errors
                        $exception = 1;
                    } elsif ($element =~ m/^SOAP-ENV:Fault$/) {
                        # baserv will throw a SOAP-ENV:Fault
                        $soap_fault = 1;
                    }
                    %element_attributes = %attrs;
                },
                End   => sub {
                    my ($expat, $element, %attrs) = @_;
                    if ($element =~ m/^ProbeDataSection$/) {
                        $probe_data_section = undef;
                    } elsif ($element =~ m/^Wafer$/) {
                        $wafer_id = undef;
                        $wafer_scribe = undef;
                    } elsif ($element =~ m/^Process$/) {
                        $process_id = undef;
                        $run_id = undef;
                    } elsif ($element =~ m/^ExceptionSection$/) {
                        $exception = 0;
                    } elsif ($element =~ m/^SOAP-ENV:Fault$/) {
                        $soap_fault = 0;
                    }
                },
            },
        )->parse($xml_data);
    };
    if ($@) {
        my $critical_error = File::Spec->catfile($LOG_DIR, uc($SCRIPT_FILE) . '.error');
        if (open(FAILEDMESSAGE, ">$critical_error")) {
            print FAILEDMESSAGE "$xml_data";
            close(FAILEDMESSAGE);
            notify('log', "Error: Unable to parse GetProcessDataPackage message see $critical_error");
        }
        $any_error .= "\n" if $any_error;
        $any_error .= "$@";
    }
    if ($any_error) {
        if ($lot_id) {
            # provide LotId as context for the error if it is available
            return(PrbLocale::ptrack_error($lot_id, $any_error), undef, undef);
        } else {
            return(PrbLocale::probe_tracking_server_error($any_error), undef, undef);
        }
    } else {
        return(undef, \%{$probe_data{'LotAttributes'}}, \%{$probe_data{'WaferAttributes'}}, \%{$probe_data{'ProcessAttributes'}}, \%{$probe_data{'ReticleData'}}, \%{$probe_data{'PartAttributes'}}, \%{$probe_data{'ProcessDefinitionData'}}, \%scribe_table);
    }
}

###############################################################################
# Description:
#     obtain lot attributes from Manufacturing Execution System
#     Unlike Probe Attributes which are name/value pairs
#     MES Attributes may contain multiple values for each attribute
#     this function will obtain the attributes from MES, and will
#     format the response as a hash of arrays
# Returns:
#     $status   - 0 : success
#                 1 : MIPC fail or timeout, $mes_attr will describe failure
#     $mes_attr - attribute hash for success, error message for fail
#     $mes_meta - MES Lot properties
# Globals:
#     %OPT,
###############################################################################
sub get_mes_attributes {
    my ($lot_id) = @_;
    time_it('get_mes_attributes');
    # Note: there is a lot of information available from MES, most is not
    # needed, and will be discarded, since we are only trying to obtain MES
    # attributes and some general lot info, the output is filtered.
    my $soapBody = "<MESLotInfo>" .
                       "<Input>" .
                           "<Lot>" .
                               "<LotId>$lot_id</LotId>" .
                           "</Lot>" .
                       "</Input>" .
                       "<Output>" .
                           "<Lot>" .
                               "<LotProperty/>" .
                               "<LotAttrList>" .
                                   "<LotAttr>" .
                                       "<Name/>" .
                                       "<LotAttrValueList>" .
                                           "<LotAttrValue>" .
                                               "<Value/>" .
                                           "</LotAttrValue>" .
                                       "</LotAttrValueList>" .
                                   "</LotAttr>" .
                               "</LotAttrList>" .
                               "<CarrierMap/>" .
                               "<TravStep>" .
                                   "<TrackInFlag/>" .
                               "</TravStep>" .
                               "<WaferList/>" .
                           "</Lot>" .
                       "</Output>" .
                   "</MESLotInfo>";
    my ($status, $reply) = send_receive_mipc_soap($OPT{'site'}, $MESSRV, $soapBody);
    if ($status) {
        return(1, $reply, undef) if wantarray;
        return($reply) if defined wantarray;
    }
    else {
        my ($parse_status, $attr_ref, $meta_ref, undef, undef, undef) = parse_batch_stage_controller_response($reply);
        time_it('get_mes_attributes', 'end');
        if ($parse_status) {
            return(1, $parse_status, undef) if wantarray;
            return($parse_status) if defined wantarray;
        } else {
            # to avoid adding more hashes, combine additional info with the %meta_hash
            return(0, $attr_ref, $meta_ref) if wantarray;
            return($attr_ref) if defined wantarray;
        }
    }
}

###############################################################################
# Description:
#     set Manufacturing Execution System lot attributes
# Returns:
#     $status - 0 or undef : success
#               localized error for fail
# Globals:
#     $SCRIPT_FILE, $MESSRV, %OPT
###############################################################################
sub set_mes_attributes {
    my ($lot_id, $multi_value, %attr_list) = @_;
    time_it('set_mes_attributes');
    my $soapBody = "<MESLotChange>" .
                       "<Input>" .
                           "<Application>$SCRIPT_FILE</Application>" .
                           "<User>0</User>" .
                           "<Comment/>" .
                           "<LotList>" .
                               "<Lot>" .
                                   "<LotId>$lot_id</LotId>" .
                                   "<LotAttrList>";
    foreach my $corr_item_no (keys %attr_list) {
        my $set_complete = 0;
        foreach my $attr (split /(.{20})/, $attr_list{$corr_item_no}) {
            # split above will return empty values interspersed with 20 character chunks
            # of the desired attribute value, I don't understand why
            if (length($attr) and !$set_complete) {
                $set_complete = 1;
                $soapBody .=           "<LotAttr>" .
                                           "<Action>SetValue</Action>" .
                                           "<CorrItemNo>$corr_item_no</CorrItemNo>" .
                                           "<Value>$attr</Value>" .
                                       "</LotAttr>";
            } elsif (length($attr) and $multi_value) {
                $soapBody .=           "<LotAttr>" .
                                           "<Action>AddValue</Action>" .
                                           "<CorrItemNo>$corr_item_no</CorrItemNo>" .
                                           "<Value>$attr</Value>" .
                                       "</LotAttr>";
            }
        }
        if (!$set_complete) {
            $soapBody .=               "<LotAttr>" .
                                           "<Action>SetValue</Action>" .
                                           "<CorrItemNo>$corr_item_no</CorrItemNo>" .
                                           "<Value/>" .
                                       "</LotAttr>";
        }
    }
    $soapBody .=                   "</LotAttrList>" .
                               "</Lot>" .
                           "</LotList>" .
                       "</Input>" .
                   "</MESLotChange>";
    time_it('set_mes_attributes', 'end');
    my ($status, $reply) = send_receive_mipc_soap($OPT{'site'}, $MESSRV, $soapBody);
    
    if ($status)
    {
        return(PrbLocale::change_attribute_error($lot_id, $reply));
    }
    else
    {
        my $soap_error = check_for_soap_error($reply);
        if ($soap_error) {
            return(PrbLocale::change_attribute_error($lot_id, $soap_error));
        }
    }
    return(undef);
}

###############################################################################
# Description:
#     parses the BatchRetrieve from Batch Stage Controller or the
#     MESLotInfo from MES, using a stream XML parser
#     Note: there is a lot of information in the BatchRetrieve
#           wafers can be assigned individually for processing
#           and the load port / chamber can be assigned
# Returns:
#     $status      - 0 or undef : success
#                    non-zero indicates MIPC fail or timeout
#     $mes_attr     - lot attribute hash
#     $mes_meta     - lot properties hash
#     $recipe_param - recipe information hash [opt]
#     $recipe_meta  - recipe meta-data hash [opt]
#     $batch_meta   - almost everytyhing else [opt]
# Globals:
#     %BATCH_LIST
###############################################################################
sub parse_batch_stage_controller_response {
    my ($xml_data) = @_;
    my (%mes_attr, %mes_meta, %traveler_hash, %recipe_param, %recipe_meta, %batch_meta);
    my (%indexed_mes_attr, %indexed_mes_meta, %indexed_recipe_param, %indexed_recipe_meta, %indexed_batch_meta);
    my ($attr_name, $lot_properties, $soap_fault, $lot_attr, $traveler_info, $carrier_map, $slot, $error);
    my ($recipe_info, $module_info, $param_info, $wafer_info, $instruct_info, $wafer_status, $wafer_attr);
    my ($output_node);
    my ($module_id, $param_id, $equip_id);
    my ($wafer_state, $wafer_scribe);
    my (%temp_recipe_param, %temp_recipe_meta);
    eval {
        my $xp = XML::Parser->new(
            Style     => 'Stream',
            Handlers  => {
                Char  => sub {
                    my ($expat, $string) = @_;
                    if ($lot_properties) {
                        if ($expat->current_element !~ m/^LotProperty$/) {
                            $mes_meta{$expat->current_element} = $string;
                        }
                    } elsif ($soap_fault) {
                        if ($expat->current_element =~ m/^StatusText$/i) {
                            $error .= "\n" if $error;
                            $error .= $string;
                        }
                    } elsif ($lot_attr) {
                        # attempt to handle xml markup (i.e. &amp;)
                        # there must be a better way to do this
                        if ($expat->current_element =~ m/^Name$/) {
                            $attr_name .= $string;
                        } elsif ($expat->current_element =~ m/^Value$/) {
                            push @{$mes_attr{$attr_name}}, $string;
                        }
                    } elsif ($traveler_info) {
                        if (($expat->current_element =~ m/^CorrItemNo$/) or ($expat->current_element =~ m/^CorrItemDesc$/)) {
                            push @{$traveler_hash{$expat->current_element}}, $string;
                        } elsif ($expat->current_element !~ m/^TravStep$/) {
                            $traveler_hash{$expat->current_element} = $string;
                        }
                    } elsif ($carrier_map) {
                        if ($expat->current_element =~ m/^SlotNo$/) {
                            $slot = $string;
                        } elsif ($slot) {
                            # place under CarrierSlotList, indexed by slot in %mes_meta
                            $mes_meta{CarrierSlotList}{$slot}{$expat->current_element} = $string;
                        } else {
                            # place under CarrierMap to avoid name conflicts
                            $mes_meta{CarrierMap}{$expat->current_element} = $string;
                        }
                    } elsif ($recipe_info) {
                        if ($expat->current_element =~ m/^Id$/) {
                            if ($param_info) {
                                $param_id = $string;
                            } elsif ($module_info) {
                                $module_id = $string;
                            } else {
                                my $parent = lc( ( $expat->context )[-2] );
                                $temp_recipe_meta{$parent} = $string;
                            }
                        } elsif ($expat->current_element =~ m/^Val$/) {
                            if ($module_info) {
                                $temp_recipe_param{$module_id}{$param_id} = $string;
                            } elsif ($param_info) {
                                $temp_recipe_param{$param_id} = $string;
                            }
                        } elsif ($expat->current_element =~ m/^EquipId$/) {
                            $equip_id = $string;
                        } elsif ($instruct_info and $expat->current_element =~ m/^Description$/) {
                            $temp_recipe_meta{'instructions'} .= "\n" if $temp_recipe_meta{'instructions'};
                            $temp_recipe_meta{'instructions'} .= $string;
                        } elsif (!$param_info and !$module_info) {
                            $temp_recipe_meta{$expat->current_element} = $string;
                            if ($expat->current_element =~ m/^ProcessName$/) {
                                $temp_recipe_meta{'process'} = $string;
                            }
                        }
                    } elsif ($wafer_info and $wafer_status) {
                        if ($expat->current_element =~ m/^WaferState$/) {
                            $wafer_state = $string;
                        } elsif ($expat->current_element =~ m/^WaferScribe$/) {
                            $wafer_scribe = $string;
                        } elsif ($wafer_attr) {
                            # attempt to handle xml markup (i.e. &amp;)
                            # there must be a better way to do this
                            if ($expat->current_element =~ m/^Name$/) {
                                $attr_name .= $string;
                            } elsif (($expat->current_element =~ m/^Value$/) and $wafer_scribe) {
                                push @{$mes_meta{'WaferAttr'}{$wafer_scribe}{$attr_name}}, $string;
                            }
                        }
                    } else {
                        $batch_meta{$expat->current_element} = $string;
                    }
                },
                Start => sub {
                    my ($expat, $element, %attrs) = @_;
                    if ($element =~ m/^LotProperty$/) {
                        $lot_properties = 1;
                    } elsif ($element =~ m/^SOAP-ENV:Fault$/) {
                        $soap_fault = 1;
                    } elsif ($element =~ m/^Name$/) {
                        $attr_name = '';
                    } elsif ($element =~ m/^LotAttr$/ ) {
                        $lot_attr = 1;
                    } elsif ($element =~ m/^TravStep$/) {
                        $traveler_info = 1;
                    } elsif ($element =~ m/^CarrierMap$/) {
                        $carrier_map = 1;
                        undef $slot;
                    } elsif ($element =~ m/^WaferList$/) {
                        $wafer_info = 1;
                    } elsif ($element =~ m/^ProcessJobList$/) {
                        if (!$wafer_info) {
                            $recipe_info = 1;
                        }
                    } elsif ($element =~ m/^Module$/) {
                        $module_info = 1;
                    } elsif ($element =~ m/^Param$/) {
                        $param_info = 1;
                    } elsif ($element =~ m/^Equip$/) {
                        %temp_recipe_param = ();
                        %temp_recipe_meta = ();
                    } elsif ($element =~ m/^Instruction$/) {
                        $instruct_info = 1;
                    } elsif ($element =~ m/^WaferStatus$/) {
                        undef $wafer_state;
                        undef $wafer_scribe;
                        $wafer_status = 1;
                    } elsif ($element =~ m/^Output$/) {
                        $output_node = 1;
                    } elsif ($element =~ m/^Batch$/) {
                        if ($output_node) {
                            %mes_attr = ();
                            %mes_meta = ();
                            %traveler_hash = ();
                            %recipe_param = ();
                            %recipe_meta = ();
                            %batch_meta = ();
                        }
                    } elsif ($element =~ m/^WaferAttr$/) {
                        $wafer_attr = 1;
                    }
                },
                End   => sub {
                    my ($expat, $element, %attrs) = @_;
                    if ($element =~ m/^LotProperty$/) {
                        $lot_properties = 0;
                    } elsif ($element =~ m/^SOAP-ENV:Fault$/) {
                        $soap_fault = 0;
                    } elsif ($element =~ m/^LotAttr$/) {
                        $lot_attr = 0;
                    } elsif ($element =~ m/^TravStep$/) {
                        $traveler_info = 0;
                    } elsif ($element =~ m/^CarrierMap$/) {
                        $carrier_map = 0;
                    } elsif ($element =~ m/^WaferList$/) {
                        $wafer_info = 0;
                    } elsif ($element =~ m/^ProcessJobList$/) {
                        $recipe_info = 0;
                    } elsif ($element =~ m/^Module$/) {
                        $module_info = 0;
                    } elsif ($element =~ m/^Param$/) {
                        $param_info = 0;
                    } elsif ($element =~ m/^Equip$/) {
                        if ($recipe_info) {
                            %{$recipe_param{$equip_id}} = %temp_recipe_param;
                            %{$recipe_meta{$equip_id}} = %temp_recipe_meta;
                        }
                    } elsif ($element =~ m/^Instruction$/) {
                        $instruct_info = 0;
                    } elsif ($element =~ m/^WaferStatus$/) {
                        if ($wafer_state and $wafer_scribe) {
                            $mes_meta{WaferStatus}{$wafer_scribe} = $wafer_state;
                        }
                        $wafer_status = 0;
                    } elsif ($element =~ m/^Output$/) {
                        $output_node = 0;
                    } elsif ($element =~ m/^Batch$/) {
                        if ($output_node) {
                            %{$indexed_mes_attr{$batch_meta{'LotId'}}} = %mes_attr;
                            %{$indexed_mes_meta{$batch_meta{'LotId'}}} = %mes_meta;
                            %{$indexed_mes_meta{$batch_meta{'LotId'}}{'TravStep'}} = %traveler_hash;
                            %{$indexed_recipe_meta{$batch_meta{'LotId'}}} = %recipe_meta;
                            %{$indexed_recipe_param{$batch_meta{'LotId'}}} = %recipe_param;
                            %{$indexed_batch_meta{$batch_meta{'LotId'}}} = %batch_meta;
                            # summarize the batch information in a global hash
                            $BATCH_LIST{$batch_meta{'LotId'}}{'BatchId'} = $batch_meta{'BatchId'};
                            $BATCH_LIST{$batch_meta{'LotId'}}{'SchedState'} = $batch_meta{'SchedState'};
                            my $mainframe_staged; # indicates lot staged to mainframe
                            foreach my $equipment (keys %recipe_meta) {
                                if (($recipe_meta{$equipment}{'Selected'} =~ /YES/i) and ($recipe_meta{$equipment}{'LotId'} =~ $batch_meta{'LotId'})) {
                                    if ($equipment !~ /$TESTER_ID/i) {
                                        push @{$BATCH_LIST{$batch_meta{'LotId'}}{'Equipment'}}, $equipment;
                                    } else {
                                        $mainframe_staged = 1;
                                    }
                                }
                            }
                            if ($mainframe_staged and ($OPT{'stage_to_mf'} or $NO_CHILD_EQUIPMENT) and !$BATCH_LIST{$batch_meta{'LotId'}}{'Equipment'}) {
                                push @{$BATCH_LIST{$batch_meta{'LotId'}}{'Equipment'}}, $TESTER_ID;
                            }
                        }
                    } elsif ($element =~ m/^WaferAttr$/) {
                        $wafer_attr = 0;
                    }
                },
            },
        )->parse($xml_data);
    };
    if ($@) {
        my $critical_error = File::Spec->catfile($LOG_DIR, uc($SCRIPT_FILE) . '.error');
        if (open(FAILEDMESSAGE, ">$critical_error")) {
            print FAILEDMESSAGE "$xml_data";
            close(FAILEDMESSAGE);
            notify('log', "Error: Unable to parse BatchRetrieve message see $critical_error");
        }
        $error = "$@";
    }
    if ($error) {
        return($error, undef, undef, undef, undef, undef);
    } elsif (%indexed_mes_attr) {
        # parsing a BatchRetrieve
        return(undef, \%indexed_mes_attr, \%indexed_mes_meta, \%indexed_recipe_param, \%indexed_recipe_meta, \%indexed_batch_meta);
    } else {
        # parsing an MESLotInfo
        # to avoid adding more hashes, combine additional info with the %mes_meta
        $mes_meta{'TravStep'} = \%traveler_hash;
        return(undef, \%mes_attr, \%mes_meta, undef, undef, undef);
    }
}

###############################################################################
# Description:
#     obtain recipe parameters from GeRM
#     using lotrecipe or procrecipe
# Returns:
#     $status   - 0 : success
#                 1 : MIPC fail or timeout, $germLotInfo will describe failure
#     $germLotInfo - general lot info hash for success, error message for fail
#     $equipParam  - equipment recipe parameter hash
#     $equipMeta   - hash describing equipment parameters
#     $germLotDetail -  MES lot info hash (only available if we route through MESSRV)
# Globals:
#     $ENGR_REQUEST, $GERMSRV, %OPT
###############################################################################
sub get_germ_info {
    my ($lot_id, $card_config) = @_;
    push @FUNCTION_TRACE, "get_germ_info($lot_id, $card_config)";
    time_it('get_germ_info');
    my $parameter_index = 1;
    my $query;
    if ($OPT{'process_type'} and $EQUIP_STATE_ALLOW{'process_run'} and $ENGR_REQUEST) {
        # request the recipe by process name
        $query = "procrecipe eq=\"$TESTER_ID\" process=\"$ENGR_REQUEST\" facility_name=\"$SITE_CFG{'GeRMFacility'}{$OPT{'site'}}\"";
    } else {
        # request the recipe by lot_id
        $query = "lotrecipe lotid=\"$lot_id\" eq_count=\"1\" eq.1=\"$TESTER_ID\" include_lot_status";
        if ($card_config !~ m /none/i) {
            $query .=
            " ${GERM_PARAM_NAME_KEYWORD}.${parameter_index}${GERM_PARAM_NAME_EXTENSION}=\"PROBE CARD CONFIG\" ${GERM_PARAM_VALUE_KEYWORD}.${parameter_index}${GERM_PARAM_VALUE_EXTENSION}=\"$card_config\"";
            ++$parameter_index;
        }
        if ($ENGR_REQUEST) {
            $REQUEST = $ENGR_REQUEST;
            if ($PrbLocale::EngrRequest{$ENGR_REQUEST}) {
                # send the hash value to GeRM, the key is selected by operator (for localization)
                $REQUEST = $PrbLocale::EngrRequest{$ENGR_REQUEST};
            }
            $query .= " ${GERM_PARAM_NAME_KEYWORD}.${parameter_index}${GERM_PARAM_NAME_EXTENSION}=\"ENGINEERING_REQUEST\" ${GERM_PARAM_VALUE_KEYWORD}.${parameter_index}${GERM_PARAM_VALUE_EXTENSION}=\"${REQUEST}\"";
            ++$parameter_index;
        } else {
            $REQUEST = '';
        }
    }
    my ($status, $reply) = send_receive_mipc($OPT{'site'}, $GERMSRV, $query);
    if ($status) {
        return(1, $reply, undef, undef, undef);
    }
    else {
        my %lotStatus;
        my %processParameters;
        my %processModuleParameters;
        my %equipData;
        my %moduleData;
        my %germLotInfo;
        my $itemIndex;   # numeric
        my $equipIndex;  # numeric
        my $moduleIndex; # numeric
        my $itemType;
        my $itemValue;
        my $instructions; # for now return a scalar concatenation of all
        my $token;
        foreach $token (quotewords('\s+', 0, $reply)) {
            if (!$token) {
                # avoid 'uninitialized value in pattern match' errors
                # I don't know how they get by the foreach
            } elsif (($itemType, $itemIndex, $itemValue) = $token =~ /ls([nv])\.(\d+)=\"?(.+)\"?/ ) {
                # Lot Status
                $lotStatus{$itemIndex}{$itemType} = $itemValue;
            } elsif (($equipIndex, $itemType, $moduleIndex, $itemIndex, $itemValue) = $token =~ /eq\.(\d+)\.(pmp.*)\.(\d+)\.(\d+)=\"?(.+)\"?/ ) {
                # Process Module Parameters returned with lotrecipe
                $processModuleParameters{$equipIndex}{$moduleIndex}{$itemIndex}{$itemType} = $itemValue;
            } elsif (($itemType, $moduleIndex, $itemIndex, $itemValue) = $token =~ /(pmp.*)\.(\d+)\.(\d+)=\"?(.+)\"?/ ) {
                # Process Module Parameters returned with procrecipe
                $processModuleParameters{1}{$moduleIndex}{$itemIndex}{$itemType} = $itemValue;
            } elsif (($equipIndex, $itemType, $itemIndex, $itemValue) = $token =~ /eq\.(\d+)\.(pp.*)\.(\d+)=\"?(.+)\"?/ ) {
                # Process Parameters returned with lotrecipe
                $processParameters{$equipIndex}{$itemIndex}{$itemType} = $itemValue;
            } elsif (($itemType, $itemIndex, $itemValue) = $token =~ /(pp.*)\.(\d+)=\"?(.+)\"?/ ) {
                # Process Parameters returned with procrecipe
                $processParameters{1}{$itemIndex}{$itemType} = $itemValue;
            } elsif (($equipIndex, $itemType, $itemIndex, $itemValue) = $token =~ /eq\.(\d+)\.(instr)\.(\d+)=\"?(.+)\"?/ ) {
                # Instructions returned with lotrecipe
                $instructions .= "\n" if $instructions;
                $instructions .= $itemValue;
            } elsif (($itemType, $itemIndex, $itemValue) = $token =~ /(instr)\.(\d+)=\"?(.+)\"?/ ) {
                # Instructions returned with procrecipe
                $instructions .= "\n" if $instructions;
                $instructions .= $itemValue;
            } elsif (($equipIndex, $itemValue) = $token =~ /eq\.(\d+)=\"?(.+)\"?/ ) {
                # EquipId returned with lotrecipe
                $equipData{$equipIndex}{'EquipId'} = $itemValue;
            } elsif (($itemValue) = $token =~ /eq=\"?(.+)\"?/ ) {
                # EquipId returned with procrecipe
                $equipData{1}{'EquipId'} = $itemValue;
            } elsif (($equipIndex, $moduleIndex, $itemValue) = $token =~ /eq\.(\d+)\.pmnn\.(\d+)=\"?(.+)\"?/ ) {
                # Module Data returned with lotrecipe
                $moduleData{$equipIndex}{$moduleIndex} = $itemValue;
            } elsif (($moduleIndex, $itemValue) = $token =~ /pmnn\.(\d+)=\"?(.+)\"?/ ) {
                # Module Data returned with procrecipe
                $moduleData{1}{$moduleIndex} = $itemValue;
            } elsif (($equipIndex, $itemType, $itemValue) = $token =~ /eq\.(\d+)\.([^=]+)=\"?(.+)\"?/ ) {
                $equipData{$equipIndex}{$itemType} = $itemValue;
            } elsif (($itemType, $itemValue) = $token =~ /([^=]+)=\"?(.+)\"?/ ) {
                $germLotInfo{$itemType} = $itemValue;
            }
        }
        if (!$germLotInfo{'MSGSTATUS'}) {
            return(1, $PrbLocale::Error{'germ_parse'}, undef, undef, undef);
        } elsif ($germLotInfo{'MSGSTATUS'} !~ /SUCCESS/i) {
            if ($germLotInfo{'meserr'}) {
                return(1, $germLotInfo{'meserr'}, undef, undef, undef);
            } elsif ($germLotInfo{'MESERR'}) {
                return(1, $germLotInfo{'MESERR'}, undef, undef, undef);
            } else {
                return(1, $reply, undef, undef, undef);
            }
        }
        # restructure information to make it easier to access
        my %germLotDetail;
        my %equipParam;
        my %equipMeta;
        my $equipId;
        my $moduleName;
        foreach $itemIndex (keys %lotStatus) {
            $germLotDetail{$lotStatus{$itemIndex}{'n'}} = $lotStatus{$itemIndex}{'v'};
        }
        foreach $equipIndex (keys %processParameters) {
            $equipId = $equipData{$equipIndex}{'EquipId'};
            foreach $itemIndex (keys %{$processParameters{$equipIndex}}) {
                # don't propagate blank values, but allow zero
                if ((defined $processParameters{$equipIndex}{$itemIndex}{'ppv'}) and
                    ($processParameters{$equipIndex}{$itemIndex}{'ppv'} or ($processParameters{$equipIndex}{$itemIndex}{'ppv'} eq '0'))) {
                    $equipParam{$equipId}{$processParameters{$equipIndex}{$itemIndex}{'ppnn'}} = $processParameters{$equipIndex}{$itemIndex}{'ppv'};
                }
            }
        }
        foreach $equipIndex (keys %processModuleParameters) {
            $equipId = $equipData{$equipIndex}{'EquipId'};
            foreach $moduleIndex (keys %{$processModuleParameters{$equipIndex}}) {
                $moduleName = $moduleData{$equipIndex}{$moduleIndex};
                foreach $itemIndex (keys %{$processModuleParameters{$equipIndex}{$moduleIndex}}) {
                    # don't propagate blank values, but allow zero
                    if ((defined $processModuleParameters{$equipIndex}{$moduleIndex}{$itemIndex}{'pmpv'}) and
                        ($processModuleParameters{$equipIndex}{$moduleIndex}{$itemIndex}{'pmpv'} or ($processModuleParameters{$equipIndex}{$moduleIndex}{$itemIndex}{'pmpv'} eq '0'))) {
                        $equipParam{$equipId}{$moduleName}{$processModuleParameters{$equipIndex}{$moduleIndex}{$itemIndex}{'pmpnn'}} = $processModuleParameters{$equipIndex}{$moduleIndex}{$itemIndex}{'pmpv'};
                    }
                }
            }
        }
        foreach $equipIndex (keys %equipData) {
            $equipId = $equipData{$equipIndex}{'EquipId'};
            foreach $itemType (keys %{$equipData{$equipIndex}}) {
                if ($itemType ne 'EquipId') {
                    $equipMeta{$equipId}{$itemType} = $equipData{$equipIndex}{$itemType};
                }
            }
            if ($instructions) {
                $equipMeta{$equipId}{'instructions'} = $instructions;
            }
        }
        # some useful parameters are returned differently if we queried by process name or lot_id
        foreach $itemType ('process', 'recipe', 'recipe_hold_count') {
            if ($germLotInfo{$itemType}) {
                $equipMeta{$equipId}{$itemType} = $germLotInfo{$itemType};
                $germLotInfo{$itemType} = ();
            }
        }
        time_it('get_germ_info', 'end');
        return(0, \%germLotInfo, \%equipParam, \%equipMeta, \%germLotDetail, $instructions);
    }
}

###############################################################################
# Description:
#     converts the ProcessDefinitionData returned from GetProcessDataPackage
#     into the PROCESS_LIST hash for backward compatibility
#     and configures the override_pid_list with process IDs
# Returns:
#     nothing
# Globals:
#     @EXCLUDE_MODES, %PROCESS_LIST
###############################################################################
sub configure_process_list {
    my ($process_definition) = @_;
    my @override_processes;
    my %no_duplicated_process_list;
    my $pid_user_option;  # will contain Process ID and description
    %PROCESS_LIST = ();
    # these are sorted by MenuNo, but the granularity is large
    foreach my $pid (sort { ${$process_definition}{$a}{'MenuNo'} <=> ${$process_definition}{$b}{'MenuNo'} } keys %{$process_definition}) {
        my $FabStepName = ${$process_definition}{$pid}{'FabStepName'};
        my $ModeDesc = ${$process_definition}{$pid}{'ModeDesc'};
        if (!grep /^${ModeDesc}$/, @EXCLUDE_MODES) {
            foreach my $definition_item (keys %{${$process_definition}{$pid}}) {
                if ($definition_item !~ /FabStepName/) {
                    $PROCESS_LIST{$FabStepName}{$pid}{$definition_item} = ${$process_definition}{$pid}{$definition_item};
                }
            }
            $pid_user_option = "$pid - ${$process_definition}{$pid}{'ProcessDesc'}";
            # see Rev 6543, some groups requested $ModeDesc ne 'PRODUCTION', other groups did not want to restrict
            if (!defined $no_duplicated_process_list{$pid_user_option}) {
                # Process ID list used for over-ride, no duplicates
                push @override_processes, $pid_user_option;
                # I don't know why I assigned to the ModeDesc?????
                $no_duplicated_process_list{$pid_user_option} = ${$process_definition}{$pid}{'ModeDesc'};
            }
        }
    }
    if ($OPT{'pid_sort'}) {
        (@override_processes) = sort @override_processes;
    }
    notify('debug', Data::Dumper->Dump([\%PROCESS_LIST], [qw(*PROCESS_LIST)]));
    tk_configure_options('override_pid_list', @override_processes);
}

###############################################################################
# Description:
#     configures the pid_list with processes appropriate for a given step
# Returns:
#     nothing
# Globals:
#     %PROCESS, %PROCESS_LIST
###############################################################################
sub configure_pid_selections {
    my ($tracking_step, $process_id) = @_;
    my @pid_choices;
    my $selected_process;
    foreach my $ProcessId (sort keys %{$PROCESS_LIST{$tracking_step}}) {
        if ($PROCESS_LIST{$tracking_step}{$ProcessId}{'ModeDesc'} =~ /^PRODUCTION$/i) {
            $PROCESS{'production'} = "$ProcessId - $PROCESS_LIST{$tracking_step}{$ProcessId}{'ProcessDesc'}";
        } else {
            push @pid_choices, "$ProcessId - $PROCESS_LIST{$tracking_step}{$ProcessId}{'ProcessDesc'}";
        }
        if ($process_id and ($process_id =~ /^$ProcessId$/i)) {
            $selected_process = "$ProcessId - $PROCESS_LIST{$tracking_step}{$ProcessId}{'ProcessDesc'}";
        }
    }
    # production process should be the first choice, place it at the front of the array
    unshift @pid_choices, $PROCESS{'production'} if $PROCESS{'production'};
    tk_configure_options('pid_list', @pid_choices);
    if ($selected_process) {
        $PROCESS{'selected'} = $selected_process;
    } elsif ($OVERRIDE{'requested'}) {
        $PROCESS{'selected'} = $PROCESS{'correlate'} if $PROCESS{'correlate'};
    } else {
        $PROCESS{'selected'} = $PROCESS{'production'};
    }
    # reset Engineering Request Browse Entry
    tk_pid_selected();
}

###############################################################################
# Description:
#     determines which wafers will be tested
#     in an interrupt recovery mode wafers that have been committed but are
#     not in a DataComplete, DataAbort, or Processed state will be tested
#     in a non interrupt recovery mode wafers selected in the GeRM Quick Carrier
#     Definition will be tested
#     in some circumstances the operator will be allowed to select wafers
#     for processing, but that will happen outside this function
# Returns:
#     $status - undef : success
#               localized error for fail
# Globals:
#     $GERM_PROCESS, $GERM_RECIPE, $REPROBE_ALLOWED, $INTERRUPT_RECOVERY
#     %LOAD_PORT, %GERM_EQUIP_PARAM, %CARRIER_USER_COPY, %MES_META,
#     %PROCESS_LIST
###############################################################################
sub setup_wafer_level_testing {
    my ($recipe_source) = @_;
    push @FUNCTION_TRACE, "setup_wafer_level_testing($recipe_source)";
    my $current_germ_process = $GERM_PROCESS ? $GERM_PROCESS : '';
    my $current_germ_recipe = $GERM_RECIPE ? $GERM_RECIPE : '';
    $INTERRUPT_RECOVERY = ();
    %CARRIER_USER_COPY = ();
    foreach my $prober (keys %LOAD_PORT) {
        foreach my $cassette (keys %{$LOAD_PORT{$prober}}) {
            if (($LOAD_PORT{$prober}{$cassette}{'status'} eq 'available') and
                 $LOAD_PORT{$prober}{$cassette}{'lot_id'}) {
                $LOAD_PORT{$prober}{$cassette}{'reprobe'} = ();
                $LOAD_PORT{$prober}{$cassette}{'previous_rev'} = ();
                my $card_config = $NO_PROBECARD ? 'none' : $PCARD_DATA{$prober}{'bit_config_id'};
                my $lot_id = $LOAD_PORT{$prober}{$cassette}{'lot_id'};
                my $previous_germ_process = defined $MES_ATTR{$lot_id}{'PRB GERM PROCESS'} ? join('', @{$MES_ATTR{$lot_id}{'PRB GERM PROCESS'}}) : '';
                my $previous_germ_recipe = defined $MES_ATTR{$lot_id}{'PRB GERM RECIPE'} ? join('', @{$MES_ATTR{$lot_id}{'PRB GERM RECIPE'}}) : '';
                my $germ_quick_cdm;
                my $quick_cdm;
                my $max_run_id = 0;  # not currently used, but maintained just in case
                my $found_run_id;    # Production modes allow only '00', non-production may be '00' to '99'
                my $same_job_run_id; # backward compatibility, perhaps this can be removed
                my %process_state;    # may be useful for display or additional interrupt recovery
                # for 'independent' lots the config file is currently responsible for setting 'process_id' and 'job_name'
                my $process_id = $OPT{'independent'} ? $LOAD_PORT{$prober}{$cassette}{'process_id'} : $PROCESS_STEP{'pid'};
                my $job_to_run = $OPT{'independent'} ? $LOAD_PORT{$prober}{$cassette}{'job_name'} : $JOB_NAME;
                foreach my $equip_id (keys %{$GERM_EQUIP_PARAM{$card_config}{$lot_id}}) {
                    if (defined $GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{'Quick Carrier Definition Map'}) {
                        $germ_quick_cdm = $GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{'Quick Carrier Definition Map'}{'Wafer Selection'};
                    }
                }
                foreach my $run_id (keys %{$PRB_PROCESS_ATTR{$lot_id}{$process_id}}) {
                    if (($run_id =~ /^\d+$/) and ($run_id >= $max_run_id) and ($run_id <= 98)) {
                        $max_run_id = int($run_id) + 1;
                    }
                    if (!(defined $LOAD_PORT{$prober}{$cassette}{'run_id'}) or ($LOAD_PORT{$prober}{$cassette}{'run_id'} eq $run_id)) {
                        $found_run_id = $run_id;
                        # Lehi wanted to run wafers through multiple step Engineering experiments, and
                        # RUN_ID was supposed to distinguish the various runs.  I am not sure if that
                        # is being used, but I am attempting to preserve the old way of determining the
                        # most likely RUN_ID for the current GeRM Process/Recipe
                        foreach my $wafer_id (keys %{$PRB_PROCESS_ATTR{$lot_id}{$process_id}{$run_id}}) {
                            # Note: this will not work for param, because each wafer may have a different 'REQUESTED PROGRAM'
                            #       it is possible that we could use a pattern match, because things like
                            #       t36m, t36m_dsite, t36m_rel, t36m_rel_dsite may all be valid
                            if ($PRB_PROCESS_ATTR{$lot_id}{$process_id}{$run_id}{$wafer_id}{'REQUESTED PROGRAM'} and ($job_to_run =~$PRB_PROCESS_ATTR{$lot_id}{$process_id}{$run_id}{$wafer_id}{'REQUESTED PROGRAM'})) {
                                $same_job_run_id = $run_id;
                            }
                        }
                    }
                }
                # which RUN_ID should be used for reprobe and recovery determination?  Production modes only allow one RUN_ID,
                # but other modes are more complicated.
                $found_run_id = $same_job_run_id if defined $same_job_run_id;
                %process_state = %{$PRB_PROCESS_ATTR{$lot_id}{$process_id}{$found_run_id}} if defined $found_run_id;
                my ($assign_status, %assign_carrier) = assign_slots($lot_id, $germ_quick_cdm, %process_state);
                if ($assign_status) {
                    # error already localized
                    return($assign_status);
                }
                my @wafers_to_process;  # contains all wafers or a sample based on Quick CDM
                foreach my $slot_num (keys %assign_carrier) {
                    if ($assign_carrier{$slot_num}{'WaferState'} =~ /Committed/i) {
                        push @wafers_to_process, $assign_carrier{$slot_num}{'WaferId'};
                    }
                }
                my %process_summary;
                foreach my $wafer_id (keys %process_state) {
                    if (grep /$wafer_id/, @wafers_to_process) {
                        my $wafer_process_state = $process_state{$wafer_id}{'PROCESS STATE'};
                        if ($wafer_process_state) {
                            push @{$process_summary{$wafer_process_state}}, $wafer_id;
                        }
                        if ( defined $process_state{$wafer_id}{'PROGRAM REV ID'} ) {
                            $LOAD_PORT{$prober}{$cassette}{'previous_rev'} = $process_state{$wafer_id}{'PROGRAM REV ID'} unless $LOAD_PORT{$prober}{$cassette}{'previous_rev'};
                            if ( $LOAD_PORT{$prober}{$cassette}{'previous_rev'} ne $process_state{$wafer_id}{'PROGRAM REV ID'} ) {
                                $LOAD_PORT{$prober}{$cassette}{'previous_rev'} = 'MIXED';  # this shouldn't match any normal revision
                            }
                        }
                        if ( defined $process_state{$wafer_id}{'REQUESTED PROGRAM'} ) {
                            $LOAD_PORT{$prober}{$cassette}{'previous_test_job'} = $process_state{$wafer_id}{'REQUESTED PROGRAM'} unless $LOAD_PORT{$prober}{$cassette}{'previous_test_job'};
                            if ( $LOAD_PORT{$prober}{$cassette}{'previous_test_job'} ne $process_state{$wafer_id}{'REQUESTED PROGRAM'} ) {
                                $LOAD_PORT{$prober}{$cassette}{'previous_test_job'} = 'MIXED';
                            }
                        }                        
                    }
                }
                my @formatted_process_summary; # for logging
                my $wafers_probed = 0;
                my $waiting_data = 0;
                my @recovered_wafers;
                foreach my $wafer_process_state (keys %process_summary) {
                    push @formatted_process_summary, "$wafer_process_state=(" . join (", ", @{$process_summary{$wafer_process_state}}) . ")";
                    if (grep /$wafer_process_state/, ('Processed', 'DataRework')) {
                        $wafers_probed += scalar @{$process_summary{$wafer_process_state}};
                        $waiting_data += scalar @{$process_summary{$wafer_process_state}};
                    } elsif (grep /$wafer_process_state/, ('DataComplete', 'DataAborted')) {
                        $wafers_probed += scalar @{$process_summary{$wafer_process_state}};
                    } elsif ( $wafer_process_state ne 'DataComplete' ) {
                        foreach my $wafer_id (@{$process_summary{$wafer_process_state}}) {
                            push @recovered_wafers, $wafer_id;
                        }
                    }
                }
                notify('log', "Lot=$lot_id, RunId=$found_run_id, process_summary: @formatted_process_summary") if @formatted_process_summary;
                notify('log', "current_germ_process=$current_germ_process, previous_germ_process=$previous_germ_process, current_germ_recipe=$current_germ_recipe, previous_germ_recipe=$previous_germ_recipe");
                my $process_based_recovery = ( $current_germ_process and $previous_germ_process and
                    ($current_germ_process eq $previous_germ_process) and ($current_germ_recipe eq $previous_germ_recipe) ) ? 1 : 0;
                my $transition_recovery = ( $current_germ_process and !$previous_germ_process and (defined $same_job_run_id or scalar @recovered_wafers) ) ? 1 : 0;
                my $override_recovery = ( $recipe_source and ($recipe_source eq 'override') and (scalar @recovered_wafers) ) ? 1 : 0;
                my $skip_recovery = ( $OPT{'skip_recovery'} or ( $recipe_source and ($recipe_source eq 'germ') and ($REPROBE_ALLOWED eq 'force') ) ) ? 1: 0;
                notify('log', sprintf "Process Based Recovery:%s, Transition Recovery:%s, Override Recovery:%s, Skip Recovery:%s", $process_based_recovery, $transition_recovery, $override_recovery, $skip_recovery);
                if (!$skip_recovery and ($process_based_recovery or $transition_recovery or $override_recovery) and defined $found_run_id) {
                    foreach my $wafer_id (@wafers_to_process) {
                        if (!defined $process_state{$wafer_id}) {
                            # it is possible that Process Assets previously committed were removed using Probe Fix
                            # the wafer needs to be added back into the list of wafers to recover
                            push @recovered_wafers, $wafer_id;
                        }
                    }
                    if (scalar @recovered_wafers) {
                        # this looks like an interrupt recovery situation
                        notify('log', "Attempt to recover processing for lot=$lot_id pid=$process_id run_id=$found_run_id job=$job_to_run wafers=" . join(",", @recovered_wafers));
                        $quick_cdm = "W" . join(",", @recovered_wafers);
                        if (!defined $LOAD_PORT{$prober}{$cassette}{'run_id'}) {
                            $LOAD_PORT{$prober}{$cassette}{'run_id'} = $found_run_id;
                        }
                        $INTERRUPT_RECOVERY = 1;
                        # Recovery can occur on either the same tool or a different tool and either right after an abort or a period of time later.
                        # So may need to download a previous test job to finish testing the lot if a new test job has been released and Test Job Rev Update is set to no. 
                        # Due to the free format of non production test job names we're going to limit test job rev restoration to PRO and PROSEAS (2 step) jobs in the following format:
                        #    /^[A-Z0-9]{4}PRO(_\S+)*$/    or   /^[A-Z0-9]{4}PROSEAS(_\S+)*$/
                        # To restore a previous test program rev the program must be released a second time with the test job rev embedded in the name.  Examples:
                        #        Standard PROD job name         Restore job name
                        #           S15CPRO_1TD_F2              S15C_PR${rev}_1TD_F2
                        #           S15CPRO_C1D_F2              S15C_PR${rev}_C1D_F2   
                        #           S15CPRO                     S15C_PR${rev}                        
                        #
                        #           S15CPROSEAS_1TD_F2          S15C_PRS${rev}_1TD_F2
                        #           S15CPROSEAS_C1D_F2          S15C_PRS${rev}_C1D_F2   
                        #           S15CPROSEAS                 S15C_PRS${rev}                        
                        $PREV_TEST_JOB_REV = (defined  $LOAD_PORT{$prober}{$cassette}{'previous_rev'}) ? $LOAD_PORT{$prober}{$cassette}{'previous_rev'} : '';
                        my $prev_test_job_name = (defined  $LOAD_PORT{$prober}{$cassette}{'previous_test_job'}) ? $LOAD_PORT{$prober}{$cassette}{'previous_test_job'} : '';
                        notify('log', "prev_test_job=$prev_test_job_name, prev_test_job_rev=$PREV_TEST_JOB_REV, allow_mixed_rev_recovery=$ALLOW_MIXED_REV_RECOVERY, job_to_run:$job_to_run");
                        if (!$OPT{'independent'} and $PREV_TEST_JOB_REV and $ALLOW_MIXED_REV_RECOVERY =~ /no/i and (($job_to_run =~ /^[A-Z0-9]{4}PRO(_\S+)*$/) or ($job_to_run =~ /^[A-Z0-9]{4}PROSEAS(_\S+)*$/)) and $LOCAL_JOB_DIR) { 
                           my $design_id = substr($job_to_run,0,4);

                           my $job_string = '';
                           my $prev_test_job = '';
                           if($job_to_run =~ /^[A-Z0-9]{4}PRO(_\S+)*$/){  # pro jobs
                              $job_string = ( length($job_to_run) > 7) ? substr($job_to_run,7) : '';
                              $prev_test_job = $design_id . "_PR" . $PREV_TEST_JOB_REV . $job_string;
                           }
                           elsif($job_to_run =~ /^[A-Z0-9]{4}PROSEAS(_\S+)*$/){ # seasoning jobs for 2 step
                              $job_string = ( length($job_to_run) > 11) ? substr($job_to_run,11) : '';
                              $prev_test_job = $design_id . "_PRS" . $PREV_TEST_JOB_REV . $job_string;                           
                           }
                           
                           # if we have an old version of the requested test job or don't have the test job on the tool at all then 
                           # $NEW_TEST_JOB_PATH and $NEW_TEST_JOB_MSG will already be set to download the latest revision from earlier
                           # check for new test job.
                           
                           my $local_job_rev = PrbCfg::get_job_rev($job_to_run);
                           if($PREV_TEST_JOB_REV eq 'MIXED'){
                               my $error = PrbLocale::testrev_not_compatible($lot_id, $job_to_run, $PREV_TEST_JOB_REV, $local_job_rev);
                               return $error;                               
                           }

                           if($local_job_rev and ( $local_job_rev eq $PREV_TEST_JOB_REV)){  
                              # Test job on the tool matches previous test job.  No job update required.
                              # clear test job update variables so we don't over write the current test program with the latest rev.
                              notify('log', "Skipping test job rev update.  Local test rev $local_job_rev matches prev rev $PREV_TEST_JOB_REV.");
                              $NEW_TEST_JOB_PATH = '';
                              $NEW_TEST_JOB_MSG = '';                           
                           }
                           else{
                              # Test job is either missing from the tool or the wrong rev.  Force an update to the required revision.
                              # handles the following cases:
                              #        Test job missing, latest rev required.
                              #        Test job missing, previous rev required.
                              #        Test job on the tool but doesn't match previous revision for lot.  Latest revision required
                              #        Test job on the tool but doesn't match previous revision for lot.  back rev test job

                              # override test job name with corresponding revision specific test job name
                              notify('log', "Overriding job_name=$JOB_NAME with prev_test_job:$prev_test_job");

                              $JOB_NAME = $prev_test_job;
                              
                              my ($error, $release_epoch);
                              
                              ($error, $PREV_TEST_JOB_PATH, $release_epoch, undef,undef) =
                                  check_for_new_test_job($prev_test_job,$JOB_RELEASE_SERVER, $LOCAL_JOB_ARCHIVE_DIR, $LOCAL_JOB_DIR);
                              if($error){
                                 return $error;
                              }
                              elsif ($PREV_TEST_JOB_PATH) {
                                    $PREV_TEST_JOB_MSG = PrbLocale::new_job_available($prev_test_job, $release_epoch);
                              } 
                                
                              my %tmp = ( check_prev_testjob_error=>$error, prev_testjob_epoch=>$release_epoch, prev_testjob_msg=>$PREV_TEST_JOB_MSG );
                                
                              foreach my $key ( keys %tmp ) {
                                 if ( $tmp{$key} ) {
                                     notify('debug', "check_for_prev_test_job() - $key=>$tmp{$key}");
                                 }
                              }
                           }                   
                        }
                    } elsif ($wafers_probed) {
                        # wafers were probed using the current germ process and recipe and we are not allowing reprobes
                        if ($OPT{'bypass_sr3_reqs'} && ($REPROBE_ALLOWED =~ /yes/i)) {
                            notify('debug', Data::Dumper->Dump([\%process_state], [qw(*PROCESS_STATES)]));
                            notify('log', 'Skipping reprobe error - ' . PrbLocale::reprobe_error($lot_id, $process_id, %process_state));
                        } 
                        else {   
                            return(PrbLocale::reprobe_error($lot_id, $process_id, %process_state));
                        }
                    }
                } elsif ( $wafers_probed and $recipe_source and ($recipe_source eq 'germ') and ($REPROBE_ALLOWED eq 'no') ) {
                    return(PrbLocale::reprobe_error($lot_id, $process_id, %process_state));
                } elsif ($wafers_probed) {
                    $LOAD_PORT{$prober}{$cassette}{'reprobe'} = 1;
                }
                if (!defined $LOAD_PORT{$prober}{$cassette}{'run_id'}) {
                    # per drace 14-June-2011, we do not want to automatically assign RUN_ID because of
                    # complexities in obtaining previously probed data
                    $LOAD_PORT{$prober}{$cassette}{'run_id'} = '00';
                    notify('log', "Automatically assigned RUN_ID='$LOAD_PORT{$prober}{$cassette}{'run_id'}' to Lot=$lot_id PID='$process_id' on $prober");
                }
                # if not in an interrupt recovery mode $quick_cdm will be from GeRM (or undef)
                $quick_cdm = $germ_quick_cdm unless $quick_cdm;
                if (!$INTERRUPT_RECOVERY) {
                    # remove 'PROCESS STATE', but leave other context if we are not in interrupt recovery
                    # that should prevent wafers previously committed from being processed
                    foreach my $wafer_id (keys %process_state) {
                        delete $process_state{$wafer_id}{'PROCESS STATE'} if defined $process_state{$wafer_id}{'PROCESS STATE'};
                    }
                }
                my ($status, %updated_carrier) = assign_slots($lot_id, $quick_cdm, %process_state);
                if ($status) {
                    # error already localized
                    return($status);
                } else {
                    # create 2 deep copies, one can be edited by user
                    foreach my $slot_num (keys %updated_carrier) {
                        foreach my $carrier_item (keys %{$updated_carrier{$slot_num}}) {
                            $LOAD_PORT{$prober}{$cassette}{'carrier'}{$slot_num}{$carrier_item} = $updated_carrier{$slot_num}{$carrier_item};
                            $CARRIER_USER_COPY{$prober}{$cassette}{$slot_num}{$carrier_item} = $updated_carrier{$slot_num}{$carrier_item};
                        }
                    }
                }
                if ($OPT{'carrier'}) {
                    # enable the carrier map display button
                    $W{"${prober}_${cassette}_map"}->configure(-state => 'normal',);
                }
            }
        }
    }
    update_wafer_counts();
    return(undef);
}

# Slot selection - for wafer sampling or testing specific wafers without
# physically splitting lots is supported by Quick Carrier Definition Map (QCDM)
# in Probe and Carrier Definition Map (CDM) in FAB and inline parametric
#
# QCDM supports a wafer selection syntax, consisting of one or more wafer
# selection expressions separated by semicolon, i.e.
# <selection_expression>[,<selection_expression>]+
# The <selection_expression> may be one of the following:
# All
# W<wafer_number|wafer_id|wafer_scribe>[,<wafer_number|wafer_id|wafer_scribe>]+
# S<slot_num>[,<slot_num>]+
# R<number_of_wafers>[<start_range>-<end_range>]
#
# Example:
# W1234-02,CT29J300SED0,9;R2[1-25]
# This would select wafer_id=1234-02, the first wafer found that had a wafer number 9,
# wafer with scribe=CT29J300SED0, and any 2 random wafers in slots 1 to 25
#
# This selection criteria causes some challenges when implementing restart recovery.
# To integrate restart recovery we could validate that the Processing State of wafers
# previously probed appears to match the slot selection criteria from QCDM, and
# then probe only the wafers that are not in a 'DataComplete' state,
# or we could ignore any QCDM and process any wafer that has been 'Committed' in a previous
# Run, or we could present the current state to a user and allow them to adjust
# what needs to be probed.
#
# QCDM is defined as free-form text in GeRM, this allows the user to make grammatical
# errors in the syntax.  Some errors could be allowed, but that would annoy some users
# because it would imply that we were thinking for them, a feature that many of us
# dislike in a computer application.
sub assign_slots {
    my ($lot_id, $quick_cdm, %process_state) = @_;
    my $any_error;
    my @selected_slots;
    my @selected_random;
    my %wafer_lookup;      # cross reference wafer elements to slot
    my %local_carrier_definition;
    # WaferId is available in 300mm MES_META 'CarrierSlotList'
    # for 200mm it is only available in probe data
    my %wafer_id_lookup;
    foreach my $wafer_id (keys %{$PRB_WFR_META{$lot_id}}) {
        $wafer_id_lookup{$PRB_WFR_META{$lot_id}{$wafer_id}{'SCRIBE'}} = $wafer_id;
    }
    # there seems to be a bug in CarrierMap info returned with MESLotInfo, it seems that when
    # wafers are scrapped the data is inconsistent with the CarrierMap info returned with
    # CARRIER_MAP_INFO or MESCarrierMapInfo.  Performing a Probe LotCheck does not seem to
    # fix the issue, at least at TECH
    # it also seems that the WaferId element is missing for wafers that do not match
    #
    # determine if WaferId is available for any wafer, i.e. we are using MES Wafer Level Tracking
    my $mes_wafer_id_found;
    foreach my $slot_num (keys %{$MES_META{$lot_id}{'CarrierSlotList'}}) {
        if ($MES_META{$lot_id}{'CarrierSlotList'}{$slot_num}{'WaferId'}) {
            $mes_wafer_id_found = 1;
            last;  # break out of foreach loop
        }
    }
    # reset all wafers and create wafer_lookup
    foreach my $slot_num (keys %{$MES_META{$lot_id}{'CarrierSlotList'}}) {
        my $wafer_id;
        my $wafer_scribe = $MES_META{$lot_id}{'CarrierSlotList'}{$slot_num}{'WaferScribe'};
        if ($MES_META{$lot_id}{'CarrierSlotList'}{$slot_num}{'LotId'} and ($MES_META{$lot_id}{'CarrierSlotList'}{$slot_num}{'LotId'} ne $lot_id)) {
            # FOUP may contain wafers from different lots, ignore these
        } else {
            if ($MES_META{$lot_id}{'CarrierSlotList'}{$slot_num}{'WaferId'}) {
                $wafer_id = $MES_META{$lot_id}{'CarrierSlotList'}{$slot_num}{'WaferId'};
            } elsif ($wafer_id_lookup{$wafer_scribe}) {
                $wafer_id = $wafer_id_lookup{$wafer_scribe};
            } elsif ($mes_wafer_id_found and $OPT{'carrier_fix'}) {
                notify('log', "MES CarrierSlotList missing WaferId for scribe=$wafer_scribe");
            } else {
                # unable to determine the wafer_id, mismatch with MES and Probe Tracking
                return(PrbLocale::mes_probe_tracking_carrier_mismatch($lot_id, $wafer_scribe));
            }
        }
        if ($wafer_id) {
            $local_carrier_definition{$slot_num}{'WaferId'} = $wafer_id;
            $local_carrier_definition{$slot_num}{'WaferState'} = $UNASSIGNED_SLOT;
            $local_carrier_definition{$slot_num}{'WaferScribe'} = $wafer_scribe;
            if ((my $wafer_num) = $wafer_id =~ /^\d{3}\w-(\d{2})$/) {
                $wafer_lookup{'WAFER_NUM'}{int $wafer_num} = $slot_num;
            }
            $wafer_lookup{'WAFER_ID'}{$wafer_id} = $slot_num;
            $wafer_lookup{'WAFER_SCRIBE'}{$wafer_scribe} = $slot_num;
        }
    }
    # for backward compatibility - if a lot is scrapped we allow it to be probed with certain restrictions
    # however, the MES_META CarrierSlotList may not exist - use Probe Data to populate the Carrier
    if (!(scalar (keys %local_carrier_definition)) and $SCRAPPED_WAFERS and $EQUIP_STATE_ALLOW{'scrapped'}) {
        foreach my $wafer_id (keys %{$PRB_WFR_META{$lot_id}}) {
            if ($PRB_WFR_ATTR{$lot_id}{$wafer_id}{'WAFER_STATUS'} =~ /SCRAPPED/i) {
                my $slot_num = $PRB_WFR_ATTR{$lot_id}{$wafer_id}{'SLOT NUMBER'};
                next unless $slot_num;
                $local_carrier_definition{$slot_num}{'WaferId'} = $wafer_id;
                $local_carrier_definition{$slot_num}{'WaferState'} = $UNASSIGNED_SLOT;
                $local_carrier_definition{$slot_num}{'WaferScribe'} = $PRB_WFR_META{$lot_id}{$wafer_id}{'SCRIBE'};
            }
        }
    }
    # define hash elements for empty slots (assumes 25 slots in the cassette)
    for (my $slot_num = 1; $slot_num <= 25; ++$slot_num) {
        $local_carrier_definition{$slot_num}{'WaferState'} = $EMPTY_SLOT unless defined $local_carrier_definition{$slot_num};
    }
    if(!$quick_cdm){
       # wafers haven't been selected.
       if(!$NO_OPERATOR_REQUIRED){
          # In manual mode force wafer selection.
			 $quick_cdm = 'None';
		 }
		 else{
			 # In auto mode select all wafers.
			 # For dynamic travelers, default wafer selection in GeRM should be 'None' if forced wafer selection is desired 
			 $quick_cdm = 'All';
		 }	
	 }
    $quick_cdm =~ s/\s//g;   # remove spaces
    if ($quick_cdm =~ /^All$/i) {
        # select all wafers
        foreach my $slot_num (keys %local_carrier_definition) {
            if ($local_carrier_definition{$slot_num}{'WaferState'} eq $UNASSIGNED_SLOT) {
                $local_carrier_definition{$slot_num}{'WaferState'} = 'Committed';
            }
        }
    } elsif ($quick_cdm =~ /^None$/i) {
        # special selection criteria that forces user to select wafers for reprobe
    } else {
        foreach my $selection_expression (split /;/, $quick_cdm) {
            if ((my $slot_csv, undef) = $selection_expression =~ /^S((\d+,?)+)$/i) {
                # Selection by slot - Example: S1,3,7
                foreach my $slot_num (split ",", $slot_csv) {
                    if (!defined $local_carrier_definition{$slot_num}) {
                        $any_error .= "\n" if $any_error;
                        $any_error .= PrbLocale::qcdm_selection_not_available($lot_id, "S$slot_num");
                    } else {
                        push @selected_slots, $slot_num;
                    }
                }
            } elsif ((my $wafer_selection) = $selection_expression =~ /^W(.+)$/i) {
                # Selection by wafer - Example: W1,7616-09,CT29J271SEC6
                # This is a wafer selection list, additional checking is needed
                foreach my $wafer_criteria (split ",", $wafer_selection) {
                    if ($wafer_criteria =~ /^\d{3}\w-\d{2}$/) {
                        # looks like a wafer-id
                        if (!defined $wafer_lookup{'WAFER_ID'}{$wafer_criteria}) {
                            $any_error .= "\n" if $any_error;
                            $any_error .= PrbLocale::qcdm_selection_not_available($lot_id, "W$wafer_criteria");
                        } else {
                            push @selected_slots, $wafer_lookup{'WAFER_ID'}{$wafer_criteria};
                        }
                    } elsif ($wafer_criteria =~ /^\d+$/) {
                        # looks like a wafer number
                        if (!defined $wafer_lookup{'WAFER_NUM'}{int $wafer_criteria}) {
                            $any_error .= "\n" if $any_error;
                            $any_error .= PrbLocale::qcdm_selection_not_available($lot_id, "W$wafer_criteria");
                        } else {
                            push @selected_slots, $wafer_lookup{'WAFER_NUM'}{int $wafer_criteria};
                        }
                    } elsif (!defined $wafer_lookup{'WAFER_SCRIBE'}{$wafer_criteria}) {
                        $any_error .= "\n" if $any_error;
                        $any_error .= PrbLocale::qcdm_selection_not_available($lot_id, "W$wafer_criteria");
                    } else {
                        push @selected_slots, $wafer_lookup{'WAFER_SCRIBE'}{$wafer_criteria};
                    }
                }
            } elsif ($selection_expression =~ /^R\d+\[\d+-\d+\]$/i) {
                push @selected_random, $selection_expression;
            } else {
                $any_error .= "\n" if $any_error;
                $any_error .= PrbLocale::qcdm_expression_error($selection_expression);
            }
        }
        foreach my $slot_num (@selected_slots) {
            if ($local_carrier_definition{$slot_num}{'WaferState'} ne $UNASSIGNED_SLOT) {
                $any_error .= "\n" if $any_error;
                $any_error .= PrbLocale::qcdm_duplicate_selection($lot_id, $local_carrier_definition{$slot_num}{'WaferScribe'});
            } else {
                $local_carrier_definition{$slot_num}{'WaferState'} = 'Committed';
            }
        }
        # wafers not previously selected are available for random selection
        foreach my $selection_expression (@selected_random) {
            my ($random_count, $random_start, $random_end) = $selection_expression =~ /^R(\d+)\[(\d+)-(\d+)\]$/i;
            my @available_slots;
            my @pre_selected_slots;  # from previous runs (likely interrupt recovery)
            my $assigned_count = 0;
            my $available_for_random_selection = 0;
            foreach my $slot_num (keys %local_carrier_definition) {
                if (($slot_num >= $random_start) and ($slot_num <= $random_end) and ($local_carrier_definition{$slot_num}{'WaferState'} eq $UNASSIGNED_SLOT)) {
                    ++$available_for_random_selection;
                    if ($process_state{$local_carrier_definition{$slot_num}{'WaferId'}}{'PROCESS STATE'} and ($assigned_count < $random_count) ) {
                        $local_carrier_definition{$slot_num}{'WaferState'} = 'Committed';
                        ++$assigned_count;
                        push @pre_selected_slots, $slot_num;
                    } else {
                        push @available_slots, $slot_num;
                    }
                }
            }
            if ( $random_count <= $available_for_random_selection or ( exists $PrbCfg::PlatformCfg{'skip_rand_waf_count_check'} and                                                           
                                                                       $PrbCfg::PlatformCfg{'skip_rand_waf_count_check'} ) ) {
                for ( ; $assigned_count < $random_count; ++$assigned_count) {
                    my $available_slot_idx = int(rand scalar @available_slots);
                    $local_carrier_definition{$available_slots[$available_slot_idx]}{'WaferState'} = 'Committed';
                    # Remove this slot number from the array so it doesn't get chosen again.
                    splice @available_slots, $available_slot_idx, 1;
                }
            } else {
                notify('log', "Error: QCDM requested $random_count wafers in range [$random_start-$random_end], only $available_for_random_selection available");
                $any_error .= "\n" if $any_error;
                $any_error .= PrbLocale::qcdm_randomize_error($lot_id, $selection_expression, scalar @available_slots);
            }
        }
    }
    if (%process_state) {
        # interrupt recovery mode, populate the correct state for any wafers still unassigned
        foreach my $slot_num (keys %local_carrier_definition) {
            if (($local_carrier_definition{$slot_num}{'WaferState'} eq $UNASSIGNED_SLOT) and $process_state{$local_carrier_definition{$slot_num}{'WaferId'}}{'PROCESS STATE'}) {
                $local_carrier_definition{$slot_num}{'WaferState'} = $process_state{$local_carrier_definition{$slot_num}{'WaferId'}}{'PROCESS STATE'};
            }
            if ($local_carrier_definition{$slot_num}{'WaferId'}) {
                $local_carrier_definition{$slot_num}{'Context'} = PrbLocale::format_process_summary($lot_id, $local_carrier_definition{$slot_num}{'WaferId'}, %{$process_state{$local_carrier_definition{$slot_num}{'WaferId'}}});
            }
        }
    }
    return ($any_error, %local_carrier_definition);
}

###############################################################################
# Description:
#     update the variable indicating how many wafers will be tested
# Returns:
# Globals:
#    %LOAD_PORT, %CARRIER_USER_COPY
###############################################################################
sub update_wafer_counts {
    foreach my $prober (keys %LOAD_PORT) {
        foreach my $cassette (keys %{$LOAD_PORT{$prober}}) {
            if (($LOAD_PORT{$prober}{$cassette}{'status'} eq 'available') and
                 $LOAD_PORT{$prober}{$cassette}{'lot_id'}) {
                my $wafer_count = 0;
                foreach my $slot_num (keys %{$CARRIER_USER_COPY{$prober}{$cassette}}) {
                    if ($CARRIER_USER_COPY{$prober}{$cassette}{$slot_num}{'WaferState'} and ($CARRIER_USER_COPY{$prober}{$cassette}{$slot_num}{'WaferState'} =~ /Committed/i)) {
                        ++$wafer_count;
                    }
                }
                $LOAD_PORT{$prober}{$cassette}{'quantity'} = $wafer_count;
            }
        }
    }
}

###############################################################################
# Description:
#     determine if a new test job is available
# Input:
#     $test_job                - name of the Test Job
#     $test_job_release_server - path to released test job archives
#     $local_archives          - path to local copy of test job archives
#     $local_jobs              - uncompressed local test jobs
# Returns:
#     $status        - non-zero value for error (localized when possible)
#     $release_path  - path to test job on release server (undef if not avail.)
#     $release_epoch - released job epoch if different than local archive
#     $local_path    - path to local test job archive (undef if not avail.)
#     $local_epoch   - local job archive epoch if it is the only one avail.
# Globals:
#     none
###############################################################################
sub check_for_new_test_job {
    my ($test_job, $test_job_release_server, $local_archives, $local_jobs) = @_;
    my $job_path = File::Spec->catfile($local_jobs, $test_job);
    my $job_pattern = qw/^(\d{10}_)?/ . ${test_job} . qw(\.(tgz|zip|tar\.gz)$);
    # subroutine return values
    my ($any_error, $release_path, $release_epoch, $local_path, $local_epoch);

    my ($status, @files) = find_files($test_job_release_server, $job_pattern);
    if (!$status and scalar @files) {
        notify('debug', sprintf "check_testjob():Found %d files on server matching job pattern", scalar @files);
        my $rel_stat = stat($files[0]);
        if (!$rel_stat) {
            $any_error = PrbLocale::stat_fail($files[0], $!);
        } else {
            $release_path = $files[0];
            if (-d $job_path) {
                # the desired Test Job is available locally
                # try to determine if the release server has a newer version available
                my $local_archive_path = File::Spec->catfile($local_archives, basename($release_path));
                my $local_stat = stat($local_archive_path);
                if (!$local_stat || ($rel_stat->mtime != $local_stat->mtime) || ($rel_stat->size != $local_stat->size)) {
                    # new job available
                    notify('debug', "check_testjob() - New Job available");
                    $release_epoch = $rel_stat->mtime;
                }
            }
        }
    } else {
        # job is not available on the release server, check for a local archive
        notify('debug', "check_testjob() - Job not on release server, check local");
        ($status, @files) = find_files($local_archives, $job_pattern);
        if (!$status and scalar @files) {
            my $local_stat = stat($files[0]);
            if (!$local_stat) {
                $any_error = PrbLocale::stat_fail($files[0], $!);
            } else {
                # the job is available locally, but was not found on the release server
                $local_path = $files[0];
                $local_epoch = $local_stat->mtime;
                notify('debug', "check_testjob() - Local job only found - localPath: $local_path  local_epoch: $local_epoch");
            }
        } else {
            $any_error = PrbLocale::job_not_available($test_job, $test_job_release_server, $local_archives);
        }
    }
    return($any_error, $release_path, $release_epoch, $local_path, $local_epoch);
}

###############################################################################
# Description:
#     determine if a new move table is available
# Returns:
#     non-zero value for error
# Globals:
#     $LOCAL_MOVE_TABLE_DIR, $NEW_MOVE_TABLE_MSG
#     $NEW_MOVE_TABLE_PATH
###############################################################################
sub check_for_new_move_table {
    my ($step_table, $move_table_release_server) = @_;
    my $move_table_path = File::Spec->catfile($LOCAL_MOVE_TABLE_DIR, $step_table);
    # Note: TECH is not planning on including a timestamp or Rev in the move table name
    my $move_table_pattern = qw/^(\d{10}_)?/ . ${step_table} . qw/(_\d\.\d+)?$/;
    $NEW_MOVE_TABLE_PATH = '';
    my ($status, @files) = find_files($move_table_release_server, $move_table_pattern);
    if (!$status and scalar @files) {
        my $rel_stat = stat($files[0]);
        if (!$rel_stat) {
            return(PrbLocale::stat_fail($files[0], $!));
        } else {
            $NEW_MOVE_TABLE_PATH = $files[0];
            if (-f $move_table_path) {
                my $local_stat = stat($move_table_path);
                if (!$local_stat) {
                    return(PrbLocale::stat_fail($move_table_path, $!));
                } else {
                    if ($rel_stat->mtime > $local_stat->mtime) {
                        # new move table available
                        $NEW_MOVE_TABLE_MSG = PrbLocale::step_table_available($step_table, $rel_stat->mtime);
                    }
                }
            }
        }
    }
    return(undef);
}

###############################################################################
# Description:
#     obtain Test Job from release server and uncompress to local directory
# Returns:
#     non-zero value for error
# Globals:
#     $CURRENT_STATE, $LOCAL_JOB_ARCHIVE_DIR
###############################################################################
sub download_test_job {
    my ($test_job_source_archive, $test_job_destination, $local_job_archive) = @_;
    $local_job_archive = $LOCAL_JOB_ARCHIVE_DIR unless $local_job_archive;
    my $zip_archive = File::Spec->catfile($local_job_archive, basename($test_job_source_archive));
    my $status;
    my $any_error;
    if ($CURRENT_STATE ne 'idle') {
        $any_error = $PrbLocale::Error{'not_idle'};
    } elsif ($status = cleanup_old_archives($local_job_archive, basename($test_job_destination))) {
        $any_error = $status;
    } elsif ($status = copy_file($test_job_source_archive, $zip_archive)) {
        $any_error = $status;
    } elsif ($status = remove_legacy_job_files()) {
        $any_error = $status;
    } elsif ($status = uncompress_file($zip_archive, $test_job_destination)) {
        $any_error = $status;
    } else {
        $NEW_JOB = $test_job_destination;
        notify('log', "UPDATED_JOB source=$test_job_source_archive destination=$NEW_JOB");
    }

    return($any_error);
}

###############################################################################
# Description:
#     previous menu maintained files indicating when test jobs were accessed
#     and released, these files need to be cleaned up if we need to revert
#     to that version of Menu
#
# Returns:
#     non-zero value for error
# Globals:
#     $JOB_NAME, $JOB_META_DIR
###############################################################################
sub remove_legacy_job_files {
    my $pattern = qw(^) . $JOB_NAME . qw(\.(access|release)\.\d+$);
    if ($JOB_META_DIR and -e $JOB_META_DIR) {
        my ($status, @files) = find_files($JOB_META_DIR, $pattern);
        if (!$status and scalar @files) {
            return(remove_files(@files));
        }
    }
    return(0);
}

###############################################################################
# Description:
#     verify minimum set of parameters are available, and that Test Job
#     and Move Table are up to date, advances to next setup screen if no
#     errors detected
# Returns:
#     non-zero value for error
# Globals:
#     $DESIGN_ID, $LOCAL_MOVE_TABLE_DIR, $LOCAL_OPERATION_MSG
#     $NEW_TEST_JOB_MSG, $LOCAL_JOB_DIR, $PROBE_SCRAPPED
#     $LOCAL_OPERATION_OK, $UPDATE_TEST_JOB, $NEW_TEST_JOB_PATH
#     $NEW_MOVE_TABLE_MSG, $UPDATE_MOVE_TABLE,  $SCRAPPED_WAFERS,
#     $MOVE_TABLE_SERVER, $JOB_RELEASE_SERVER, $JOB_NAME,
#     $PROBE_ON_HOLD, $INTERRUPT_RECOVERY, $ALLOW_MIXED_REV_RECOVERY
#     $TEMPERATURE, $MOVE_TABLE, $PROBE_FACILITY, %PROCESS_STEP,
#     %RECIPE, %OVERRIDE, %OPT
###############################################################################
sub tk_check_parameters {
    my ($recipe_source, $test_job_name, $chuck_temperature, $process, $step_table) = @_;
    my $arg_list = "$recipe_source, $test_job_name, ";
    $arg_list .= $chuck_temperature if defined $chuck_temperature;
    $arg_list .= ", $process,";
    $arg_list .= $step_table if defined $step_table;
    push @FUNCTION_TRACE, "tk_check_parameters($arg_list)";
    my $any_error;
    my $status;
    my $test_job_basename;  # allow relative path
    my $test_job_subpath;
    my $test_job_ext;
    my $step_table_basename;
    my $step_table_subpath;
    my $step_table_ext;
    my ($process_id) = $process =~ /^([^ ]+)/;
    my %lots;       # hash used to avoid redundant calls for lot split across heads
    foreach my $prober (keys %LOAD_PORT) {
        foreach my $cassette (keys %{$LOAD_PORT{$prober}}) {
            if (($LOAD_PORT{$prober}{$cassette}{'status'} eq 'available') and
                 $LOAD_PORT{$prober}{$cassette}{'lot_id'}) {
                $lots{$LOAD_PORT{$prober}{$cassette}{'lot_id'}} = ();
            }
        }
    }
    if ($LOCAL_JOB_DIR or $LOCAL_MOVE_TABLE_DIR) {
        notify('info', $PrbLocale::Msg{'calling_relsrv'});
    }
    if ($LOCAL_JOB_DIR) {
        # Test Job can be relative to the Release Server
        ($test_job_basename, $test_job_subpath, $test_job_ext) = fileparse($test_job_name, qr/\..*/);
        my $test_job_release_server = $JOB_RELEASE_SERVER;
        # if $test_job_subpath is a directory use that path instead of a path relative to the Release Server
        if ($test_job_subpath !~ m/^\.[\/\\]$/) {
            if (-d $test_job_subpath) {
                $test_job_release_server = $test_job_subpath;
            } else {
                $test_job_release_server = File::Spec->catfile($JOB_RELEASE_SERVER, $test_job_subpath);
            }
        }
        $NEW_TEST_JOB_MSG = '';
        $LOCAL_OPERATION_OK = '';
        $LOCAL_OPERATION_MSG = '';
        my ($release_epoch, $local_path, $local_epoch);
        ($status, $NEW_TEST_JOB_PATH, $release_epoch, $local_path, $local_epoch) =
            check_for_new_test_job($test_job_basename, $test_job_release_server, $LOCAL_JOB_ARCHIVE_DIR, $LOCAL_JOB_DIR);
        if ($status) {
            return($status);
        } elsif ($release_epoch) {
            $NEW_TEST_JOB_MSG = PrbLocale::new_job_available($test_job_basename, $release_epoch);
        } elsif ($local_path and !$NEW_TEST_JOB_PATH) {
            $LOCAL_OPERATION_MSG = PrbLocale::local_job_only($test_job_basename);
        }
        my %tmp = ( check_testjob_error=>$status, new_testjob_epoch=>$release_epoch, new_testjob_msg=>$NEW_TEST_JOB_MSG, local_job_only_msg=>$LOCAL_OPERATION_MSG, local_testjob_only=>$local_path  );
        
        foreach my $key ( keys %tmp ) {
           if ( $tmp{$key} ) {
              notify('debug', "check_for_new_test_job() - $key=>$tmp{$key}");
           }
        }

    } else {
        # this platform does not maintain jobs in a local job directory
        notify('debug', "No local testjob directory - test_job_name - $test_job_name");
        $test_job_basename = $test_job_name;
    }
    if ($LOCAL_MOVE_TABLE_DIR) {
        # for legacy reasons the move table name defaults to the design ID
        # this isn't desirable, because the stepping may be (and is) different
        # for different platforms
        # (at least it was when card configuration was not unique)
        # ideally we should get one stepping table for a particular
        # card configuration, and design ID combination

        # to retain backward compatibility if the move table name is not
        # defined, default to the design ID
        $step_table = $DESIGN_ID unless $step_table;
        ($step_table_basename, $step_table_subpath, $step_table_ext) = fileparse($step_table, qr/\..*/);
        $step_table = "${step_table_basename}${step_table_ext}";
        my $move_table_release_server = $MOVE_TABLE_SERVER;
        # if $step_table_subpath is a directory use that path instead of a path relative to the Release Server
        if ($step_table_subpath !~ m/^\.[\/\\]$/) {
            if (-d $step_table_subpath) {
                $move_table_release_server = $step_table_subpath;
            } else {
                $move_table_release_server = File::Spec->catfile($move_table_release_server, $step_table_subpath);
            }
        }
        # answers to confirm settings can be handled automatically via command line option
        $NEW_MOVE_TABLE_MSG = '';
        if ($status = check_for_new_move_table($step_table, $move_table_release_server)) {
            return($status);
        }
    }
    if ($CASCADE_INFO{'JOB_NAME'} and ($CASCADE_INFO{'JOB_NAME'} ne $test_job_basename)) {
        $any_error .= "\n" if $any_error;
        $any_error .= PrbLocale::job_not_compatible($CASCADE_INFO{'JOB_NAME'}, $test_job_basename);
    }
    # it has been requested by Production and Engineering (in Boise) not to ask
    # operator to enter Temperature when over-ride is selected
    # this may cause problems if the Test Job does not set the temperature
    if (defined $chuck_temperature and defined $CASCADE_INFO{'TEMPERATURE'} and ($CASCADE_INFO{'TEMPERATURE'} != $chuck_temperature)) {
        $any_error .= "\n" if $any_error;
        $any_error .= PrbLocale::temperature_not_compatible($CASCADE_INFO{'TEMPERATURE'}, $chuck_temperature);
    }
    notify('info', '');
    if ($status = check_process_id($process_id)) {
        $any_error .= "\n" if $any_error;
        $any_error .= $status;
    }
    if (!$any_error) {
        # initialize global variables that will be used to complete the setup
        # these are the minimum for all platforms
        $JOB_NAME = $test_job_basename;
        $TEMPERATURE = $chuck_temperature;
        $MOVE_TABLE = $step_table;
        $PROBE_FACILITY = $OPT{'site'};
        # these are head specific recipe parameters
        foreach my $prober (keys %LOAD_PORT) {
            foreach my $cassette (keys %{$LOAD_PORT{$prober}}) {
                if (($LOAD_PORT{$prober}{$cassette}{'status'} eq 'available') and
                     $LOAD_PORT{$prober}{$cassette}{'lot_id'}) {
                    my $card_config = $NO_PROBECARD ? 'none' : $PCARD_DATA{$prober}{'bit_config_id'};
                    my $lot_id = $LOAD_PORT{$prober}{$cassette}{'lot_id'};
                    # the 3rd index into %GERM_EQUIP_PARAM was $TESTER_ID, but I don't think that is correct in all cases
                    foreach my $equip_id (keys %{$GERM_EQUIP_PARAM{$card_config}{$lot_id}}) {
                        if ($GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{'TRENDING_WAFERS_COUNT'}) {
                            $LOAD_PORT{$prober}{$cassette}{'trend'} = $GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{'TRENDING_WAFERS_COUNT'};
                        }
                        if ($GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{'RUN_ID'}) {
                            $LOAD_PORT{$prober}{$cassette}{'run_id'} = $GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{'RUN_ID'};
                        }
                        my $germ_device_file;
                        if ($GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{'DEVICE_FILE'}) {
                            $germ_device_file = $GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{'DEVICE_FILE'};
                        }
                        foreach my $param_name (keys %{$GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}}) {
                            if (($param_name =~ /^CARD_TYPE_(.+)$/i) and $GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name}{'CARD_CONFIG'} and ($GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name}{'CARD_CONFIG'} eq $card_config)
                                and ($GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name}{'DEVICE_FILE'})) {
                                $germ_device_file = $GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name}{'DEVICE_FILE'};
                            }
                        }
                        if ($germ_device_file) {
                            $LOAD_PORT{$prober}{$cassette}{'prober_device_file'} = $germ_device_file;
                            notify('debug', "DEVICE_FILE '$LOAD_PORT{$prober}{$cassette}{'prober_device_file'}' for $prober specified by GeRM");
                        } else {
                            undef $LOAD_PORT{$prober}{$cassette}{'prober_device_file'};
                        }
                    }
                }
            }
        }
        my $assign_slot_status = setup_wafer_level_testing($recipe_source);
        if ($assign_slot_status) {
            return($assign_slot_status);
        }
        # 19-May-2011 drace and acameron discussed auto updating to latest Test Job and movetable
        # if we are not in an interrupt recovery, this makes behavior similar
        # to what is seen if Test Jobs and movetables are cleaned up
        # if any lot is being started in an interrupt recovery mode, GeRM parameter TESTJOB_REV_UPDATE
        # controls updating the Test Job and movetable
        my $default_update_action = '';
        if ($CURRENT_STATE eq 'idle') {
            if (($recipe_source eq 'germ') and $INTERRUPT_RECOVERY) {
                $default_update_action = $ALLOW_MIXED_REV_RECOVERY;
            } elsif (($recipe_source eq 'germ') or $OPT{'auto_confirm'}) {
                $default_update_action = 'yes';
            }
        }
        else {
             notify('debug', "CURRENT_STATE: '$CURRENT_STATE' is not idle, not setting default_update_action");
        }
        $UPDATE_TEST_JOB = $default_update_action;
        $UPDATE_MOVE_TABLE = $default_update_action;
        # answers to confirm settings can be handled automatically via command line option
        if ($OPT{'auto_confirm'}) {
            $LOCAL_OPERATION_OK = 'yes';
            $PROBE_SCRAPPED = 'yes';
            $PROBE_ON_HOLD = 'yes';
        }
        # this is a hack
        if ($recipe_source eq 'override') {
            # the platform specific config file will expect some required parameters
            %RECIPE = %OVERRIDE;
        }
        notify('debug', Data::Dumper->Dump([\%RECIPE], [qw(*RECIPE)]));
        notify('debug', Data::Dumper->Dump(
            [ $NEW_TEST_JOB_MSG, $default_update_action, $UPDATE_TEST_JOB, $NEW_MOVE_TABLE_MSG, $UPDATE_MOVE_TABLE, $ON_HOLD_WAFERS, $PROBE_ON_HOLD, $SCRAPPED_WAFERS, $PROBE_SCRAPPED, $LOCAL_OPERATION_MSG, $LOCAL_OPERATION_OK ], 
            [ qw(*NEW_TEST_JOB_MSG *default_update_action *UPDATE_TEST_JOB *NEW_MOVE_TABLE_MSG *UPDATE_MOVE_TABLE
*ON_HOLD_WAFERS *PROBE_ON_HOLD *SCRAPPED_WAFERS *PROBE_SCRAPPED *LOCAL_OPERATION_MSG *LOCAL_OPERATION_OK) ] ));
        
        if ( ($NEW_TEST_JOB_MSG and !$UPDATE_TEST_JOB) or ($NEW_MOVE_TABLE_MSG and !$UPDATE_MOVE_TABLE) or
                  ($ON_HOLD_WAFERS and !$PROBE_ON_HOLD)     or ($SCRAPPED_WAFERS and !$PROBE_SCRAPPED) or
                  ($LOCAL_OPERATION_MSG and !$LOCAL_OPERATION_OK) ) {
            # still more checks, need to parse move table, etc.
            page_to('update');
        } else {
            return(tk_confirm_settings());
        }
    }
    return($any_error);
}

# Data Collection Process ID may have been altered by user
sub tk_check_process_id {
    my ($any_error) = tk_check_parameters('germ', $RECIPE{'job_name'}, $RECIPE{'Temperature'}, $PROCESS{'selected'}, $RECIPE{'movetable'});
    if ($any_error) {
        notify('warn', $any_error);
    }
    return($any_error);
}

###############################################################################
# Description:
#     verify Data Collection Process ID is valid
#     this needs to pull from the definitive PID
#     either from $OVERRIDE{'process'}, $PROCESS{'selected'},
#     GeRM PID parameter, or PID over-written by user
#
#     verify probecard can be used with the selected data collection mode
#     verify equipment state is compatible with selected data collection mode
#     obtains probe lot and wafer process data
#     sets global variables expected by platform specific config files
# Returns:
#     non-zero value for error
# Globals:
#     %LOAD_PORT, %PCARD_DATA, %CASCADE_INFO, %PROCESS_LIST, %PROCESS_STEP,
#     %ET_STATE, %MES_META
###############################################################################
sub check_process_id {
    my ($process_id) = @_;
    push @FUNCTION_TRACE, "check_process_id($process_id)";
    my $any_error;
    my %lots;         # hash used to avoid redundant calls for lot split across heads
    my %setup_prober; # hash used to avoid redundant error messages while checking PCT
    my $apparent_step = lookup_tracking_step($process_id, $STEP_NAME);
    my $production_mode = ($apparent_step and ($PROCESS_LIST{$apparent_step}{$process_id}{'ModeDesc'} =~ /PRODUCTION/i)) ? 1 : 0;
    $ON_HOLD_WAFERS = '';
    foreach my $prober (keys %LOAD_PORT) {
        foreach my $cassette (keys %{$LOAD_PORT{$prober}}) {
            if (($LOAD_PORT{$prober}{$cassette}{'status'} eq 'available') and
                 $LOAD_PORT{$prober}{$cassette}{'lot_id'}) {
                my $lot_id = $LOAD_PORT{$prober}{$cassette}{'lot_id'};
                $lots{$lot_id} = ();
                $setup_prober{$prober} = ();
                # lots on hold can only be probed under specific conditions
                if ($MES_META{$lot_id}{'StateDesc'} =~ /Hold/i) {
                    if ($production_mode) {
                        $any_error .= "\n" if $any_error;
                        $any_error .= PrbLocale::lot_hold($lot_id, $MES_META{$lot_id}{'StateDesc'});
                    } else {
                        $ON_HOLD_WAFERS .= "\n" if $ON_HOLD_WAFERS;
                        $ON_HOLD_WAFERS .= PrbLocale::continue_with_on_hold($lot_id);
                    }
                }
            }
        }
    }

    if ($production_mode) {
        foreach my $prober (keys %setup_prober) {
            # anakashima, debmiller, psharratt want this to stop 'production' steps only
            if (!$NO_PROBECARD and ($PCARD_DATA{$prober}{'event_stops_production'} =~ /^Y(ES)?$/i)) {
                $any_error .= "\n" if $any_error;
                $any_error .= PrbLocale::card_event_code_error($PCARD_ID{$prober}, $prober, $PROCESS{'production'});
            } elsif (!$NO_PROBECARD and ($PCARD_DATA{$prober}{'state_stops_production'} =~ /^Y(ES)?$/i)) {
                $any_error .= "\n" if $any_error;
                $any_error .= PrbLocale::card_state_error($PCARD_ID{$prober}, $PCARD_DATA{$prober}{'GLS_equip_state_id'}, $prober, $PROCESS{'production'});
            }
            # 'production' steps not allowed when equipment state is 'Non-Scheduled'
            my $equipment_sub_state = $NO_CHILD_EQUIPMENT ? $ET_STATE{$TESTER_ID}{'sub_state'} : $ET_STATE{$TESTER_ID}{'child'}{$prober}{'sub_state'};
            my $equipment_state = $NO_CHILD_EQUIPMENT ? $ET_STATE{$TESTER_ID}{'state'} : $ET_STATE{$TESTER_ID}{'child'}{$prober}{'state'};
            if ($equipment_state =~ /^Non-scheduled$/i) {
                $any_error .= "\n" if $any_error;
                $any_error .= PrbLocale::process_equip_state_error($prober, $process_id, $equipment_sub_state);
            }
        }
    }
    # updated in get_probe_lot_wafer_process_data, so initialized here
    $SCRAPPED_WAFERS = '';
    notify('info', $PrbLocale::Msg{'calling_pattr'});
    foreach my $lot_id (keys %lots) {
        my ($status) = get_probe_lot_wafer_process_data($lot_id, $process_id);
        if ($status) {
            $any_error .= "\n" if $any_error;
            $any_error .= $status;
        }
    }
    if ($CASCADE_INFO{'PROCESS_ID'} and ($CASCADE_INFO{'PROCESS_ID'} ne $process_id)) {
        $any_error .= "\n" if $any_error;
        $any_error .= PrbLocale::process_not_compatible($CASCADE_INFO{'PROCESS_ID'}, $process_id);
    }
    if ($any_error) {
        return($any_error);
    } else {
        notify('info', '');
        notify('debug', Data::Dumper->Dump([\%PRB_LOT_ATTR, \%PRB_WFR_ATTR, \%PRB_WFR_META, \%PRB_PROCESS_ATTR, \%PRB_RETICLE_HISTORY, \%PRB_PART_ATTR], [qw(*PRB_LOT_ATTR *PRB_WFR_ATTR *PRB_WFR_META *PRB_PROCESS_ATTR *PRB_RETICLE_HISTORY *PRB_PART_ATTR)]));
        $PROCESS_STEP{'pid'} = $process_id;
        if ($apparent_step) {
            $PROCESS_STEP{'ProcessDesc'} = $PROCESS_LIST{$apparent_step}{$PROCESS_STEP{'pid'}}{'ProcessDesc'};
            # ProbeIS changed the keywords for the codes associated with the process id.  In the Middle Layer call
            # it was ReturnColumnNameList=..,StepCode,..,OperationCode,..,ModeCode
            # in the ProcessDefinitionData it is StepId, OperationId, ModeId
            if ($PROCESS_LIST{$apparent_step}{$PROCESS_STEP{'pid'}}{'StepId'}) {
                $PROCESS_STEP{'StepCode'} = $PROCESS_LIST{$apparent_step}{$PROCESS_STEP{'pid'}}{'StepId'};
            } elsif ($PROCESS_LIST{$apparent_step}{$PROCESS_STEP{'pid'}}{'StepCode'}) {
                $PROCESS_STEP{'StepCode'} = $PROCESS_LIST{$apparent_step}{$PROCESS_STEP{'pid'}}{'StepCode'};
            }
            $PROCESS_STEP{'StepDesc'} = $PROCESS_LIST{$apparent_step}{$PROCESS_STEP{'pid'}}{'StepDesc'};
            if ($PROCESS_LIST{$apparent_step}{$PROCESS_STEP{'pid'}}{'OperationId'}) {
                $PROCESS_STEP{'OperationCode'} = $PROCESS_LIST{$apparent_step}{$PROCESS_STEP{'pid'}}{'OperationId'};
            } elsif ($PROCESS_LIST{$apparent_step}{$PROCESS_STEP{'pid'}}{'OperationCode'}) {
                $PROCESS_STEP{'OperationCode'} = $PROCESS_LIST{$apparent_step}{$PROCESS_STEP{'pid'}}{'OperationCode'};
            }
            $PROCESS_STEP{'OperationDesc'} = $PROCESS_LIST{$apparent_step}{$PROCESS_STEP{'pid'}}{'OperationDesc'};
            if ($PROCESS_LIST{$apparent_step}{$PROCESS_STEP{'pid'}}{'ModeId'}) {
                $PROCESS_STEP{'ModeCode'} = $PROCESS_LIST{$apparent_step}{$PROCESS_STEP{'pid'}}{'ModeId'};
            } elsif ($PROCESS_LIST{$apparent_step}{$PROCESS_STEP{'pid'}}{'ModeCode'}) {
                $PROCESS_STEP{'ModeCode'} = $PROCESS_LIST{$apparent_step}{$PROCESS_STEP{'pid'}}{'ModeCode'};
            }
            $PROCESS_STEP{'ModeDesc'} = $PROCESS_LIST{$apparent_step}{$PROCESS_STEP{'pid'}}{'ModeDesc'};
        }
        notify('debug', Data::Dumper->Dump([\%PROCESS_STEP], [qw(*PROCESS_STEP)]));
        return(undef);
    }
}

###############################################################################
# Description:
#     create a list of Test Jobs for use with over-ride
#     Note: THIS CURRENTLY DOES NOT WORK IF A SUB DIRECTORY IS EXPECTED
#           RELATIVE TO THE TEST JOB RELEASE SERVER
# Returns:
#     $status - non-zero value for error, @test_job_choices will describe fail
#     \@test_job_choices - list of jobs from the Release Server
# Globals:
#     none
###############################################################################
sub tk_build_job_list {
    my ($job_wildcard, $test_job_release_server, $local_job_path) = @_;
    my $pattern = qw/^(\d{10}_)?/ . ${job_wildcard} . qw(.*\.(tgz|zip|tar\.gz));
    my @test_job_choices;
    # needs work
    my ($status, @files) = find_files($test_job_release_server, $pattern);
    if ($status) {
        return(1, @files);
    } else {
        my $job_file;
        foreach my $test_job (@files) {
            my ($test_job_basename, $test_job_subpath, $test_job_ext) = fileparse($test_job, qr/\..*/);
            # Note: TECH does not include a timestamp ( \d{10} ) in the job archive name
            if ((undef, $job_file) = $test_job_basename =~ m/^(\d{10}_)?(.+)$/) {
                push @test_job_choices, $job_file;
            }
        }
        if (scalar @test_job_choices) {
            return(0, \@test_job_choices);
        } else {
            # no Test Jobs were found on the release server, look for local jobs
            $pattern = qw(^) . ${job_wildcard};
            ($status, @files) = find_files($local_job_path, $pattern);
            if (!$status and scalar @files) {
                foreach my $test_job (@files) {
                    push @test_job_choices, basename($test_job);
                }
                return(0, \@test_job_choices);
            } else {
                return(1, PrbLocale::no_matching_job_available($job_wildcard, $JOB_RELEASE_SERVER, $LOCAL_JOB_DIR));
            }
        }
    }
}

###############################################################################
# Description:
#     utility to manage callbacks for widgets
# Returns:
#     nothing
# Globals:
#     $W
###############################################################################
sub tk_configure_callback {
    my ($widget_key, $callback_ref) = @_;
    $W{$widget_key}->configure(
        -command => sub {
            $W{$widget_key}->configure(-state => 'disabled',);
            &$callback_ref;
            $W{$widget_key}->configure(-state => 'normal',);
        },
    );
}

###############################################################################
# Description:
#     find files in a directory that match a specified regular expression
#     files returned are sorted in descending order by date (i.e. newest first)
# Returns:
#     $status - non-zero value for error, @test_job_choices will describe fail
#     @return_values - list of files
# Globals:
#     none
###############################################################################
sub find_files {
    # 'Programming Perl' - L. Wall, T. Christiansen, J. Orwant - O'Reilly
    # recommends against filename globbing for portability
    # this subroutine can be used to find files that match a pattern
    my ($directory, $pattern) = @_;
    my @files;
    my @return_values;
    if (opendir SEARCH_DIR, $directory) {
        my @files = (sort { -M "$directory/$a" <=> -M "$directory/$b" } grep /${pattern}/i, readdir SEARCH_DIR);
        closedir SEARCH_DIR;
        foreach my $file (@files) {
            push @return_values, File::Spec->catfile($directory, $file);
        }
        notify('debug', "find_files():\n" . Data::Dumper->Dump([\$directory, \$pattern, \@return_values ], [qw(*search_directory *pattern *files)]));
        return(0, @return_values);
    } else {
        return(1, PrbLocale::directory_access_fail($directory, $!));
    }
}

###############################################################################
# Description:
#     copies a file, returns localized error message on failure
#     attempts to mimic 'cp -pf', i.e.
#     unlink destination file if it exists,
#     and attempt to preserve modification and access time
#     Note: File::Copy::Recursive claims to preserve permission
# Returns:
#     $status - non-zero value for error
# Globals:
#     none
###############################################################################
sub copy_file {
    my ($source_path, $destination) = @_;
    notify('debug', "Copying $source_path to $destination");
    if (-f $destination) {
        # copy will fail if the destination is owned by a different user
        unlink $destination;  # ignore errors
    }
    my $source_stat = stat($source_path);
    if (!$source_stat) {
        return(PrbLocale::stat_fail($source_path, $!));
    } elsif (copy($source_path, $destination)) {
        utime $source_stat->atime, $source_stat->mtime, $destination;
        return(0);
    } else {
        return(PrbLocale::copy_fail($source_path, $destination, $!));
    }
}

###############################################################################
# Description:
#     removes a directory, returns localized error message on failure
# Returns:
#     $status - non-zero value for error
# Globals:
#     none
###############################################################################
sub remove_directory {
    my ($path) = @_;
    # this doesn't seem to remove hidden files or directories - PROBLEM!
    notify('debug', "remove_directory() - attempting to remove_directory: $path");   
    eval { rmtree($path, 0, 0) };
    if ($@) {
        return(PrbLocale::rmdir_fail($path, $@));
    } else {
        notify('debug', "remove_directory() - No error reported by rmtree for removal of $path");   
        if ((-d $path) and ($^O =~ /solaris/i)) {
            # it is important that the directory is removed, even if I can't
            # do this in a platform independant manner
            notify('log', "ERROR in remove_directory for path=$path");
            if (system("/bin/rm -Rf $path")) {
                return(PrbLocale::rmdir_fail($path, $!));
            }
        }
        notify('debug', "remove_directory(): $path should be removed");
        return(0);
    }
}

###############################################################################
# Description:
#     removes a file, returns localized error message on failure
# Returns:
#     $status - non-zero value for error
# Globals:
#     none
###############################################################################
sub remove_files {
    my (@files) = @_;
    unless (unlink @files) {
        return(PrbLocale::unlink_fail($!, @files));
    }
    notify('debug', "remove_files: @files");
    return(0);
}

###############################################################################
# Description:
#     uncompresses an archive (used for Test Jobs)
# Returns:
#     $status - non-zero value for error
# Globals:
#     none
###############################################################################
sub uncompress_file {
    time_it('uncompress_job');
    my ($zip_archive, $destination_path) = @_;
    my ($zip_file, $zip_dir, $zip_ext) = fileparse($zip_archive, qr/\..*/);
    my $command;
    my $result;
    my $status;
    notify('debug', "uncompress_file() - $zip_archive");

    if ($status = remove_directory($destination_path)) {
        return($status);
    } elsif ($^O =~ /win/i) {
        my $ziputil;
        if ( defined $PrbCfg::PlatformCfg{'ZipUtility'} ) {
           $ziputil = $PrbCfg::PlatformCfg{'ZipUtility'};
        } else {
            $ziputil = 'J:\\APPS\\7zip\\7za.exe';
        }
        notify('debug', "Executing ZipUtility:" . $ziputil );
        if (!-x $ziputil) {
            return(PrbLocale::no_zip_utility($ziputil));
        }
        if ($ziputil =~ m/7za?\.exe/i) {
            # -y                 : yes to all queries
            # -bd               : suppress progress indicator
            # x <archive>    : archive to extract, with full pathnames
            # -o<directory> : Where to extract contents of archive
            # In case it is local with a directory name with spaces, wrap in quotes
            $command = "\"$ziputil\" -y -bd x $zip_archive -o$destination_path";
        }
        $result = `$command`;
        if ($?) {
            notify('debug', "Error Extracting files - $?");
            return(PrbLocale::error_extracting_files($zip_archive, $destination_path, $result));
        } else {
            notify('debug', "Command '$command' returned $result");
        }
    } else {
        if (!-d $destination_path and !(mkdir $destination_path)) {
            return(PrbLocale::mkdir_fail($destination_path, $!));
        }
        if (($zip_ext eq '.tgz') || ($zip_ext eq '.tar.gz')) {
            my $tgz_archive = File::Spec->catfile($destination_path, "${zip_file}${zip_ext}");
            my $copy_status = copy_file($zip_archive, $tgz_archive);
            if ($copy_status) {
                return($copy_status);
            }
            my $tar_file = "$zip_file.tar";
            my $full_tar_path = File::Spec->catfile($destination_path, $tar_file);
            my $current_dir = cwd();
            # -q   : supress warnings
            # -f   : overwrite existing files without prompting
            $command = "gunzip -qf $tgz_archive 2>&1";
            $result = `$command`;
            if ($?) {
                return(PrbLocale::error_extracting_files($tgz_archive, $destination_path, $result));
            }
            unless (chdir $destination_path) {
                return(PrbLocale::chdir_fail($destination_path, $!));
            }
            my $tarutil = 'tar -pxf';  # default value - location depends on users PATH
            # -p   : preserve file modes and ACLs if applicable
            # -x   : extract archive
            # -f   : use tarfile argument as name of the tar file
            if (defined $PrbCfg::PlatformCfg{'TarUtility'}) {
                # the tar utility will likely contain command switches, but the first
                # parameter should be a file that exists and is executable
                my @tar_args = parse_line('\s+', 0, $PrbCfg::PlatformCfg{'TarUtility'});
                if (@tar_args and (-e $tar_args[0])) {
                    $tarutil = $PrbCfg::PlatformCfg{'TarUtility'};
                }
            }
            $command = "$tarutil $tar_file 2>&1";
            $result = `$command`;
            if ($?) {
                return(PrbLocale::error_extracting_files($tar_file, $destination_path, $result));
            } else {
                notify('debug', "Command '$command' returned $result");
            }
            unless (chdir $current_dir) {
                return(PrbLocale::chdir_fail($current_dir, $!));
            }
            if (-f $full_tar_path) {
                remove_files($full_tar_path);
            }
        } else {
            # -q   : supress warnings
            # -d   : destination directory
            $command = "unzip -q $zip_archive -d $destination_path 2>&1";
            $result = `$command`;
            if ($?) {
                return(PrbLocale::error_extracting_files($zip_archive, $destination_path, $result));
            } else {
                notify('debug', "Command '$command' returned $result");
            }
        }
    }
    time_it('uncompress_job', 'end');
    return(undef);
}

###############################################################################
# Description:
#     obtains probe card information from PCT
# Returns:
#     $status - non-zero value for error, card_info will describe fail
#     \%card_info - reference to hash containing probe card information
# Globals:
#     $TESTER_ID, %SITE_CFG, %OPT
###############################################################################
sub get_probecard_data {
    my ($card_id, $prober, $contam_type) = @_;
    time_it('get_probecard_data');
    my $probecard_data_cache = File::Spec->catfile($CACHE_DIR, "card_data_" . prober_alpha_designator($prober) . ".txt");
    my $parsed_card_info_hash_ref;
    my ($msg, $pct_subject);
    my ($status, $reply); # for MIPC communication with PCT
    my $card_id_key = sprintf "PC-%06d", $card_id;
    if (defined $PCTSRVXML and $PCTSRVXML)
    {
        $msg = "<PCT_START_CARD><Input>" .
                    "<EquipId>$prober</EquipId>" .
                    "<ProbeCardId>$card_id_key</ProbeCardId>".
                    #"<Facility>BOISE PROBE</Facility>".
                    "<Devl>NO</Devl>".   #'NO' (default) tells PCT to use the production database.
                                         #'YES' tells PCT to use the development database.
                    "<Mode>TEST</Mode>". #'TEST' tells PCT to not update the card status
                                         #'PROD' (default) tells PCT to update the status
                    "<ContamType>ALL</ContamType>".
                "</Input></PCT_START_CARD>";        
        $pct_subject = $PCTSRVXML;
    }
    else
    {
        # deprecated
        $msg = "PCT_START_CARD PROBECARD_ID='$card_id_key' EQUIP_ID='$prober' MODE='TEST' SITE_NAME='$OPT{'site'}'";
        $msg .= " CONTAM_TYPE='$contam_type'" if $contam_type;
        $pct_subject = $PCTSRV;
    }

    if ($OPT{'USE_PCT_CACHE'}) {
        $status = 1; # force read from cache
        $reply = "Offline testing"; # for logging
    } else {
        ($status, $reply) = send_receive_mipc($OPT{'site'}, $pct_subject, $msg);
    }

    time_it('get_probecard_data', 'end');
    if (!$status) {
        # reply received from PCT, attempt to parse response
        if (defined $PCTSRVXML and $PCTSRVXML) {
            ($status, $parsed_card_info_hash_ref) = parse_xmlprobecard_info($card_id_key,$reply,\$contam_type); # If not defined previously contam_type
        } else {                                                                                                # is updated to match the first recipe.  
            #depricated
            ($status, $parsed_card_info_hash_ref) = parse_probecard_info($card_id_key, $reply);
        }
    }
    if (!defined $parsed_card_info_hash_ref->{'equip_id'}) {
      $status = "PCT response was invalid.";
      undef $parsed_card_info_hash_ref;
    }
    if (!$status) {
        # PCT reply appears to be correct, cache a copy locally
        unlink $probecard_data_cache;  # ignore errors
        unless (write_file($probecard_data_cache, $reply)) {
            notify('log', PrbLocale::can_not_update_probe_card_cache($probecard_data_cache));
        }
    } else {
        # per anakashima notify via email if errors occur, other sites may want additional notification
        if (!$OPT{'USE_PCT_CACHE'} and @{$SITE_CFG{'PCT_ADMIN_MAIL'}{$OPT{'site'}}}) {
            notify_important('mail', "PCT_ERROR card=$card_id_key site=$OPT{'site'} equip=$TESTER_ID", "Sent: $msg\nTo: $pct_subject\nReceived: $reply", @{$SITE_CFG{'PCT_ADMIN_MAIL'}{$OPT{'site'}}});
        }
        if (!$OPT{'USE_PCT_CACHE'} and @{$SITE_CFG{'PCT_ADMIN_PAGE'}{$OPT{'site'}}}) {
            notify_important('mail', undef, "PCT_ERROR $reply", @{$SITE_CFG{'PCT_ADMIN_PAGE'}{$OPT{'site'}}});
        }
        if (-r $probecard_data_cache) {
            # PCT outage after hardware upgrade at MTV caused several hours of downtime
            # use cached copy if possible
            my $cached_card_info = read_file($probecard_data_cache);
            if ($cached_card_info =~ /$card_id_key/) {
                notify('log', "PCT_ERROR: Using cached copy because: $reply");
                
                if (defined $PCTSRVXML and $PCTSRVXML) {
                    ($status, $parsed_card_info_hash_ref) = parse_xmlprobecard_info($card_id_key,$cached_card_info,\$contam_type);
                } else {
                    #depricated
                    ($status, $parsed_card_info_hash_ref) = parse_probecard_info($card_id_key, $cached_card_info);                    
                }   
            }
        }
    }
    if ($parsed_card_info_hash_ref) {
        if ($contam_type) {
            my $current_contam_type = ${$parsed_card_info_hash_ref}{'contamination_type_desc'} ? ${$parsed_card_info_hash_ref}{'contamination_type_desc'} : 'MISSING';
            my $current_overtravel = ${$parsed_card_info_hash_ref}{'min_overtravel_no'} ? ${$parsed_card_info_hash_ref}{'min_overtravel_no'} : 0;
            my $sub_recipe_config_bit;
            my $sub_recipe_overtravel;
            # PCT may return 'null' for bit_config.0, that indicates the bond pad material is not valid for that card
            if ( ${$parsed_card_info_hash_ref}{'contam_type_desc.0'} and (${$parsed_card_info_hash_ref}{'contam_type_desc.0'} eq $contam_type) and
                defined ${$parsed_card_info_hash_ref}{'bit_config.0'} and (${$parsed_card_info_hash_ref}{'bit_config.0'} =~ /^\d+$/) and
                defined ${$parsed_card_info_hash_ref}{'init_min_overtravel.0'} and (${$parsed_card_info_hash_ref}{'init_min_overtravel.0'} =~ /^[+-]?[\d\.]+$/) ) {
                # cleaning recipe appears to be valid
                $sub_recipe_config_bit = ${$parsed_card_info_hash_ref}{'bit_config.0'};
                $sub_recipe_overtravel = ${$parsed_card_info_hash_ref}{'init_min_overtravel.0'};
            }
            if ( $current_contam_type eq $contam_type ) {
                # card is already associated with the desired bond pad material, the overtravel and bit_config_id
                # are correct (?).
                # Supposedly there can only be one min_overtravel setting for a bond pad material and that rule
                # is supposed to be enforced by the PCT application.  If that wasn't the case we could have
                # different overtravel in different cleaning recipes (BLOCK, WAFER, ...), then which would we use?
                # I have seen a case where min_overtravel_no is different than init_min_overtravel.0 for the
                # same bond pad material.  I am getting annoyed checking consistency with information returned from PCT.
                if ( defined $sub_recipe_overtravel and ( $sub_recipe_overtravel != $current_overtravel ) and @{$SITE_CFG{'PCT_ADMIN_MAIL'}{$OPT{'site'}}} ) {
                    notify_important('mail', "PCT_ERROR card=$card_id_key site=$OPT{'site'} equip=$TESTER_ID", "min_overtravel_no=$current_overtravel does not match init_min_overtravel.0=$sub_recipe_overtravel for '$contam_type'", @{$SITE_CFG{'PCT_ADMIN_MAIL'}{$OPT{'site'}}});
                }
            } elsif ( defined $sub_recipe_config_bit ) {
                my $current_config_bit = ${$parsed_card_info_hash_ref}{'bit_config_id'} ? ${$parsed_card_info_hash_ref}{'bit_config_id'} : 'MISSING';
                notify('debug', "Changing card=$card_id_key contamination_type_desc from '$current_contam_type' to '$contam_type', min_overtravel_no from $current_overtravel to $sub_recipe_overtravel, bit_config_id from $current_config_bit to $sub_recipe_config_bit");
                ${$parsed_card_info_hash_ref}{'contamination_type_desc'} = $contam_type;
                ${$parsed_card_info_hash_ref}{'bit_config_id'} = $sub_recipe_config_bit;
                ${$parsed_card_info_hash_ref}{'min_overtravel_no'} = $sub_recipe_overtravel;
            } else {
                return(1, PrbLocale::invalid_bond_pad_error($contam_type));
            }
        }
        return($status, $parsed_card_info_hash_ref);
    } else {
        # it is likely there was an MIPC error
        return($status, $reply);
    }
}

###############################################################################
# Description:
#     converts information from PCT into perl hash, the information
#     can be from a PCT call or from a cached response from PCT
#     some error checking is performed, and will return a non-zero
#     $status if an error is detected
# Returns:
#     $status - non-zero value for error, card_info will describe fail
#     \%card_info - reference to hash containing probe card information
###############################################################################
sub parse_probecard_info {
    my ($card_id_key, $card_info_message) = @_;
    my %card_info;
    my ($token, $name, $value);
    foreach $token (quotewords('\s+', 0, $card_info_message)) {
        if ($token and (($name, $value) = $token =~ /([^=]+)=(.+)/ )) {
            $card_info{$name} = $value;
        }
    }
    # special case for no data returned
    if ($card_info{'RESULT'}) {
        return(1, $card_info{'RESULT'});
    } elsif ($card_info{'DAT_ERROR'}) {
        return(1, $card_info{'DAT_ERROR'});
    } elsif ($card_info{'SQL_ERROR'}) {
        return(1, $card_info{'SQL_ERROR'});
    } elsif (!%card_info) {
        # PCT doesn't always return data
        return(1, $card_info_message);
    } elsif ($card_id_key and ($card_info{'equip_id'} ne $card_id_key)) {
        return(1, PrbLocale::incorrect_card_id($card_info{'equip_id'}));
    } else {
        return(0, \%card_info);
    }
}

sub parse_xmlprobecard_info {
    my ($card_id_key, $card_info_message,$contam_type_ref) = @_;
    my %card_info;
    my %Attrs;
    my %T;          #hash of current tags
    my $AttrName;
    my $bondpad;
    my $media;
    my %cleaning;
    my $mediacnt=-1;

    my $xml=XML::Parser->new(
        Handlers => 
        {
            Char => sub {
                my ($expat, $string) = @_;
                if ( $T{'Output'}) {
                    if ( !defined $T{'cleaning_config'} or !$T{'cleaning_config'} ) {
                        $Attrs{$AttrName} = $string;
                    }
                                                        # Deb Miller requested that if a lot is missing bond pad type,
                                                        # the first recipe be used.
                    elsif ($bondpad eq $$contam_type_ref) {
                        $Attrs{$AttrName.".$mediacnt"} = $string;
                    }
                }            
            },
            Start=> sub {
                my ($expat, $element, %attrs) = @_;   
                $T{$element} = 0;
                foreach my $tag (keys %T) {
                    $T{$tag} += 1;
                }            
                $AttrName = $element;
                $AttrName =~ s/__/_/g; # double underscore to single
                if ( defined $T{'cleaning_config'} and $T{'cleaning_config'} == 2  ) {
                    $bondpad = $AttrName;
                    $bondpad =~ s/_/ /g; # underscore to space
                    if (!defined $$contam_type_ref or !$$contam_type_ref) {
                        $$contam_type_ref = $bondpad;
                    }
                    
                }
                if ( defined $T{'cleaning_config'} and $T{'cleaning_config'} == 3 and 
                     $$contam_type_ref eq $bondpad ) {
                    $media = $AttrName;                    
                    $media =~ s/_/ /g; # underscore to space
                    $mediacnt += 1;
                    $Attrs{"contam_type_desc.$mediacnt"}=$bondpad;
                    $Attrs{"clean_type.$mediacnt"}=$media;
                }           
                
            },
            End=> sub {
                my ($expat, $element, %attrs) = @_;
                my @remove;
                foreach my $key (keys %T) {
                    $T{$key} -= 1;
                    push @remove, $key if $T{$key} == 0;
                }
                delete @T{@remove};
            },
        }
    );       
    $xml->parse($card_info_message);
    return (0,\%Attrs);
}

###############################################################################
# Description:
#     copies data obtained from various sources to make it easier to display
#     using Tk widgets
# Returns:
#     nothing
# Globals:
#     %LOAD_PORT, %MES_META, %CARRIER_USER_COPY
###############################################################################
sub refresh_lot_info {
    my $lot_id;
    foreach my $prober (keys %LOAD_PORT) {
        foreach my $cassette (keys %{$LOAD_PORT{$prober}}) {
            if ($LOAD_PORT{$prober}{$cassette}{'status'} eq 'available') {
                $lot_id = $LOAD_PORT{$prober}{$cassette}{'lot_id'};
                $LOAD_PORT{$prober}{$cassette}{'lot_type'} = $MES_META{$lot_id}{'LotType'};
                $LOAD_PORT{$prober}{$cassette}{'part_type'} = $MES_META{$lot_id}{'PartType'};
                if (!defined $CARRIER_USER_COPY{$prober}{$cassette}) {
                    $LOAD_PORT{$prober}{$cassette}{'quantity'} = $MES_META{$lot_id}{'CurrentQty'};
                }
            }
        }
    }
}

###############################################################################
# Description:
#     some menu features are enabled by equipment state
#     dual headed systems may allow options prior to entering a lot for a head
#     but then restrict based on that head(s) SEMI-E10 State
# Returns:
#     nothing
# Globals:
#     $NO_CHILD_EQUIPMENT, $TESTER_ID, %ET_ITEMS, %ET_STATE,
#     %LOAD_PORT, %EQUIP_STATE_ALLOW, %OPT
###############################################################################
sub refresh_setup_options {
    my @e10_state_options = ('bsc_bypass', 'override', 'mode_select', 'carrier' );
    my %temp_allow_option;
    my %allowed_states;
    foreach my $option (@e10_state_options) {
        $temp_allow_option{$option} = 0;  # initialize to disable
        @{$allowed_states{$option}} = split(',', uc($OPT{$option}));
    }
    # special case without command line option
    foreach my $special_option ('scrapped', 'hold') {
        $temp_allow_option{$special_option} = 0;
        @{$allowed_states{$special_option}} = ('ENGINEERING');
        push @e10_state_options, $special_option;
    }
    # first pass is independent of lots
    if ($NO_CHILD_EQUIPMENT) {
        my $e10_state = $ET_STATE{$TESTER_ID}{'state'};
        foreach my $option (@e10_state_options) {
            if (grep /^$e10_state$/, @{$allowed_states{$option}}) {
                $temp_allow_option{$option} = 1;
            }
        }
    } else {
        foreach my $prober (sort keys %{$ET_ITEMS{$TESTER_ID}{'child'}}) {
            my $e10_state = $ET_STATE{$TESTER_ID}{'child'}{$prober}{'state'};
            foreach my $option (keys %allowed_states) {
                if (grep /^$e10_state$/, @{$allowed_states{$option}}) {
                    $temp_allow_option{$option} = 1;
                }
            }
        }
    }
    # I believe I introduced a bug at Rev 4857, the intent was to impose additional
    # checks if a lot was being setup
    foreach my $prober (keys %LOAD_PORT) {
        foreach my $cassette (keys %{$LOAD_PORT{$prober}}) {
            if (($LOAD_PORT{$prober}{$cassette}{'status'} eq 'available') and
                 $LOAD_PORT{$prober}{$cassette}{'lot_id'}) {
                if (!$NO_CHILD_EQUIPMENT) {
                    my $e10_state = $ET_STATE{$TESTER_ID}{'child'}{$prober}{'state'};
                    foreach my $option (keys %allowed_states) {
                        if (!grep /^$e10_state$/, @{$allowed_states{$option}}) {
                            $temp_allow_option{$option} = 0;
                        }
                    }
                }
            }
        }
    }
    foreach my $option (@e10_state_options) {
        $EQUIP_STATE_ALLOW{$option} = $temp_allow_option{$option};
    }
}

###############################################################################
# Description:
#     obtain a clean copy of the Test Job from local job archive
# Returns:
#     $status - non-zero value for error
###############################################################################
sub get_clean_job {
    my ($test_job, $test_job_destination, $archive_dir) = @_;
    my $job_pattern = qw/^(\d{10}_)?/ . ${test_job} . qw(\.(tgz|zip|tar\.gz)$);
    my ($status, @files) = find_files($archive_dir, $job_pattern);
    if ($CURRENT_STATE ne 'idle') {
        return($PrbLocale::Error{'not_idle'});
    } elsif (!$status and scalar @files) {
        if ($status = uncompress_file($files[0], $test_job_destination)) {
            return($status);
        } else {
            return(undef);
        }
    } else {
        return(PrbLocale::no_job_archive($job_pattern, $archive_dir));
    }
}

###############################################################################
# Description:
#     parses the move table
# Returns:
#     $status - non-zero value for error
# Globals:
#     %LOAD_PORT, %MOVE_TABLE_INFO, %PROBER_RECIPE
###############################################################################
sub parse_move_table {
    my ($move_table_file) = @_;
    my $equiv_parts;
    my $first_part;
    require MoveTableParser;
    foreach my $prober (keys %LOAD_PORT) {
        foreach my $cassette (keys %{$LOAD_PORT{$prober}}) {
            if (($LOAD_PORT{$prober}{$cassette}{'status'} =~ /(available)|(active)/) and
                 $LOAD_PORT{$prober}{$cassette}{'lot_id'}) {
                # is this valid if LOAD_PORT status is 'active'?
                my $card_config = $PCARD_DATA{$prober}{'bit_config_id'};
                my $part_type = $LOAD_PORT{$prober}{$cassette}{'part_type'};
                my $lot_id = $LOAD_PORT{$prober}{$cassette}{'lot_id'};
                my $moveTable = new MoveTableParser::MTParser;
                if ($moveTable->ReadSteppingFile($move_table_file, $part_type, $card_config)) {
                    return(PrbLocale::error_reading_move_table($move_table_file, $moveTable->GetLineNum(), $moveTable->GetError()));
                }
                # use the DEVICE_FILE specified by GeRM, or what is in the move table
                my $germ_device_file;
                foreach my $equip_id (keys %{$GERM_EQUIP_PARAM{$card_config}{$lot_id}}) {
                    foreach my $param_name (keys %{$GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}}) {
                        if (($param_name =~ /^CARD_TYPE_(.+)$/i) and $GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name}{'CARD_CONFIG'} and ($GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name}{'CARD_CONFIG'} eq $card_config)
                            and ($GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name}{'DEVICE_FILE'})) {
                            $germ_device_file = $GERM_EQUIP_PARAM{$card_config}{$lot_id}{$equip_id}{$param_name}{'DEVICE_FILE'};
                        }
                    }
                }
                if ($germ_device_file) {
                    $LOAD_PORT{$prober}{$cassette}{'prober_device_file'} = $germ_device_file;
                    notify('debug', "DEVICE_FILE '$LOAD_PORT{$prober}{$cassette}{'prober_device_file'}' for $prober specified by GeRM");
                } elsif ($OVERRIDE{'DEVICE_FILE'}) {
                    $LOAD_PORT{$prober}{$cassette}{'prober_device_file'} = $OVERRIDE{'DEVICE_FILE'};
                    notify('debug', "DEVICE_FILE '$LOAD_PORT{$prober}{$cassette}{'prober_device_file'}' for $prober provided by override");
                } else {
                    $LOAD_PORT{$prober}{$cassette}{'prober_device_file'} = $moveTable->GetProductFile();
                    notify('debug', "DEVICE_FILE '$LOAD_PORT{$prober}{$cassette}{'prober_device_file'}' for $prober specified in Move Table");
                }
                $PROBER_RECIPE{$prober}{'DEVICE_FILE'} = $LOAD_PORT{$prober}{$cassette}{'prober_device_file'};  # deprecated
                # we have access to anything in the move table
                # I think the only thing we need is the total die, since
                # it is required in the header
                # the device file name would be good to have, since
                # prober_control / generic_daemon would not have to change
                # if it ever moved to GeRM
                $MOVE_TABLE_INFO{$card_config}{'total_die'} = $moveTable->GetTotalDie();
                $MOVE_TABLE_INFO{$card_config}{'product_file'} = $moveTable->GetProductFile();
                $MOVE_TABLE_INFO{$card_config}{'num_steps'} = $moveTable->GetNumSteps();
                $MOVE_TABLE_INFO{$card_config}{'site_map'} = $moveTable->GetSiteMap();
                # added by repeacock Rev 2966 to support Tester per site architecture
                # Note: testerSiteMap is from the optional TESTER_SITE field in the Move Table
                $MOVE_TABLE_INFO{$card_config}{'tester_site'} = $moveTable->GetTesterSites();
                $MOVE_TABLE_INFO{$card_config}{'card_x'} = $moveTable->GetColumnCount();
                $MOVE_TABLE_INFO{$card_config}{'card_y'} = $moveTable->GetRowCount();
                # some versions of GPC want to know the offset of the config block within the
                # part block, they probably shouldn't know this information
                $MOVE_TABLE_INFO{$card_config}{'config_num'} = $moveTable->GetConfigBlockOffset();
                # these items have been added for backward compatibility (alternative to PCT)
                $MOVE_TABLE_INFO{$card_config}{'FirstLastSoak'} = $moveTable->GetFirstLastSoak();
                # please note the units are now in microns
                $MOVE_TABLE_INFO{$card_config}{'planarityLimit'} = $moveTable->GetPlanarityLimit();
                $MOVE_TABLE_INFO{$card_config}{'max_overtravel'} = $moveTable->GetMaxOvertavel();
                $MOVE_TABLE_INFO{$card_config}{'overtravel'} = $moveTable->GetOvertavel();
                # this is information used by some Test Jobs
                $MOVE_TABLE_INFO{$card_config}{'min_x'} = $moveTable->GetMinX();
                $MOVE_TABLE_INFO{$card_config}{'max_x'} = $moveTable->GetMaxX();
                $MOVE_TABLE_INFO{$card_config}{'min_y'} = $moveTable->GetMinY();
                $MOVE_TABLE_INFO{$card_config}{'max_y'} = $moveTable->GetMaxY();
                # added for Teradyne, used in shared memory
                $MOVE_TABLE_INFO{$card_config}{'mtrev'} = $moveTable->GetMTRev();
                $MOVE_TABLE_INFO{$card_config}{'flat_position'} = $moveTable->GetFlat();
                $MOVE_TABLE_INFO{$card_config}{'x_die_size_um'} = $moveTable->GetXDieSize();
                $MOVE_TABLE_INFO{$card_config}{'y_die_size_um'} = $moveTable->GetYDieSize();
                if (!$first_part) {
                    $first_part = $part_type;
                    $equiv_parts = $moveTable->GetEquivParts($part_type);
                    notify('debug', "first partType=$first_part equiv_parts=$equiv_parts\n");
                } elsif (!$moveTable->AreEquivParts($first_part, $part_type)) {
                    return(PrbLocale::part_not_compatible($part_type, $first_part, $equiv_parts));
                }
            }
        }
    }
    notify('debug', Data::Dumper->Dump([\%MOVE_TABLE_INFO], [qw(*MOVE_TABLE_INFO)]));
    return(0);
}

###############################################################################
# Description:
#     Currently all platforms use flat files to transfer lot and wafer
#     attributes to the test job.  Some require special processing, Example:
#     the Vizyx does not allow spaces in the attribute name
#     the lot attributes are written to tmptravl instead of a lot attribute
#     file and there is no LotID directory created for the attribute files
#     the location of the lot attribute file is stored in the LOAD_PORT hash
# Returns:
#     $status - non-zero value for error
# Globals:
#     %LOAD_PORT, %PRB_LOT_ATTR, %PRB_WFR_ATTR, %MES_ATTR, %MES_META
###############################################################################
sub write_attributes_and_dlog_header {
    my %lots;       # hash used to avoid redundant calls for lot split across heads
    my $attr_dir;
    my $status;
    my $no_spaces_in_keyword = ($PrbCfg::PlatformCfg{'AttrNoSpaces'} and ($PrbCfg::PlatformCfg{'AttrNoSpaces'} =~ m/yes/i)) ? 1 : 0;
    my $attribute_keyword;
    my $attribute_value;
    my $attribute_delimiter = $PrbCfg::PlatformCfg{'AttrDelimiter'};

    foreach my $prober (keys %LOAD_PORT) {
        foreach my $cassette (keys %{$LOAD_PORT{$prober}}) {
            if (($LOAD_PORT{$prober}{$cassette}{'status'} eq 'available') and
                 $LOAD_PORT{$prober}{$cassette}{'lot_id'}) {
                if ($lots{$LOAD_PORT{$prober}{$cassette}{'lot_id'}}) {
                    # attributes have already been written
                    $LOAD_PORT{$prober}{$cassette}{'lot_attr_file'} = $lots{$LOAD_PORT{$prober}{$cassette}{'lot_id'}};
                } else {
                    my $lot_id = $LOAD_PORT{$prober}{$cassette}{'lot_id'};
                    if ($PrbCfg::PlatformCfg{'SkipAttrLotID'} and ($PrbCfg::PlatformCfg{'SkipAttrLotID'} =~ m/yes/i)) {
                        $attr_dir = $PrbCfg::PlatformCfg{'AttrDir'};
                    } else {
                        $attr_dir = File::Spec->catfile($PrbCfg::PlatformCfg{'AttrDir'}, $lot_id);
                        if (!-d $attr_dir and !(mkdir $attr_dir)) {
                            return(PrbLocale::mkdir_fail($attr_dir, $!));
                        }
                    }
                    # create lot level attribute file
                    # note we should scope MES and Probe attributes to avoid name conflicts
                    $LOAD_PORT{$prober}{$cassette}{'lot_attr_file'} = File::Spec->catfile($attr_dir, "$lot_id.txt");
                    if (open LOTATTRFILE, ">$LOAD_PORT{$prober}{$cassette}{'lot_attr_file'}") {
                        # Probe Lot Attributes
                        foreach my $attr_name ( sort keys %{$PRB_LOT_ATTR{$lot_id}{$lot_id}}){
                            $attribute_keyword = $attr_name;
                            if ($no_spaces_in_keyword) {
                                $attribute_keyword =~ s/\s/_/g;
                            }
                            print LOTATTRFILE "${attribute_keyword}${attribute_delimiter}$PRB_LOT_ATTR{$lot_id}{$lot_id}{$attr_name}\n";
                        }
                        # MES Lot Attributes
                        foreach my $attr_name ( sort keys %{$MES_ATTR{$lot_id}}){
                            $attribute_keyword = $attr_name;
                            if ($no_spaces_in_keyword) {
                                $attribute_keyword =~ s/\s/_/g;
                            }
                            if (scalar(@{$MES_ATTR{$lot_id}{$attr_name}}) > 1) {
                                $attribute_value = join(',', @{$MES_ATTR{$lot_id}{$attr_name}});
                            } else {
                                $attribute_value = "@{$MES_ATTR{$lot_id}{$attr_name}}";
                            }
                            print LOTATTRFILE "${attribute_keyword}${attribute_delimiter}${attribute_value}\n";
                        }
                        close LOTATTRFILE;
                        notify('debug', "Created attribute file '$LOAD_PORT{$prober}{$cassette}{'lot_attr_file'}'");
                    } else {
                        return(PrbLocale::file_open_fail($LOAD_PORT{$prober}{$cassette}{'lot_attr_file'}, 'write', $!));
                    }
                    # save the name of the lot attribute file, in case this lot is split across heads
                    $lots{$LOAD_PORT{$prober}{$cassette}{'lot_id'}} = $LOAD_PORT{$prober}{$cassette}{'lot_attr_file'};
                    # create wafer level attribute files
                    foreach my $wafer_id (sort keys %{$PRB_WFR_ATTR{$lot_id}}) {
                        my $wfr_attr_file = File::Spec->catfile($attr_dir, "$wafer_id.txt");
                        if (open WFRATTRFILE, ">$wfr_attr_file") {
                            foreach my $attr_name ( sort keys %{$PRB_WFR_ATTR{$lot_id}{$wafer_id}}){
                                $attribute_keyword = $attr_name;
                                if ($no_spaces_in_keyword) {
                                    $attribute_keyword =~ s/\s/_/g;
                                }
                                print WFRATTRFILE "${attribute_keyword}${attribute_delimiter}$PRB_WFR_ATTR{$lot_id}{$wafer_id}{$attr_name}\n";
                            }
                            my $wafer_scribe = $PRB_WFR_META{$lot_id}{$wafer_id}{'SCRIBE'};
                            if ($MES_META{$lot_id}{'WaferAttr'}{$wafer_scribe}) {
                                foreach my $attr_name ( sort keys %{$MES_META{$lot_id}{'WaferAttr'}{$wafer_scribe}}){
                                    $attribute_keyword = $attr_name;
                                    if ($no_spaces_in_keyword) {
                                        $attribute_keyword =~ s/\s/_/g;
                                    }
                                    if (scalar(@{$MES_META{$lot_id}{'WaferAttr'}{$wafer_scribe}{$attr_name}}) > 1) {
                                        $attribute_value = join(',', @{$MES_META{$lot_id}{'WaferAttr'}{$wafer_scribe}{$attr_name}});
                                    } else {
                                        $attribute_value = "@{$MES_META{$lot_id}{'WaferAttr'}{$wafer_scribe}{$attr_name}}";
                                    }
                                    print WFRATTRFILE "${attribute_keyword}${attribute_delimiter}${attribute_value}\n";
                                }
                            }
                            close WFRATTRFILE;
                            notify('debug', "Created attribute file '$wfr_attr_file'");
                        } else {
                            return(PrbLocale::file_open_fail($wfr_attr_file, 'write', $!));
                        }
                    }
                }
                # write the datalog header
                if ($status = write_dlog_lot_header($prober, $cassette)) {
                    return($status);
                }
            }
        }
    }
    return(undef);
}

###############################################################################
# Description:
#     utility that returns 'a' or 'b' based on proberID
#     supports single and dual headed systems
# Returns:
#     'a' or 'b'
# Globals:
#     none
###############################################################################
sub prober_alpha_designator {
    my ($prober) = @_;
    $prober = uc($prober);
    # relies on current naming convention, 4th character of prober should be A, B, or S
    # equipment with load port only should end in P[1-9]
    if ($prober =~ /^\w{3}([B])/) {
        return('b');
    } elsif ((my $port_id) = $prober =~ /^\w{8}P([1-9])/) {
        return(chr($port_id - 1 + ord('a')));
    } else {
        return('a');
    }
}

###############################################################################
# Description:
#     creates a datalog header, that can be sent to DFS
# Reference:
# http://edm.micron.com/cgi-bin/mtgetdoc.exe?library=mfg1&itemID=09005aef8223b3ac
# Returns:
#     $status - non-zero value for error
# Globals:
#     $JOB_NAME, $OPERATOR_ID, $MENU_VERSION, $PROBE_FACILITY, %LOAD_PORT,
#     %PCARD_DATA, %PCARD_ID, %PROCESS_STEP, %PRB_LOT_ATTR, %MOVE_TABLE_INFO,
#     %GERM_LOT_INFO
###############################################################################
sub write_dlog_lot_header {
    my ($prober, $cassette) = @_;
    my $prober_alias = uc prober_alpha_designator($prober);
    my $dual_cassette = '';
    if ($cassette eq 'rear') {
        $dual_cassette = '_dual';
    }
    $LOAD_PORT{$prober}{$cassette}{'dlog_header'} = File::Spec->catfile($PrbCfg::PlatformCfg{'HeaderDir'}, "dlog_lot_header_${prober_alias}${dual_cassette}");
    my $lot_id = $LOAD_PORT{$prober}{$cassette}{'lot_id'};
    my ($lot_prefix, $legacy_split) = $lot_id =~ /^(.{7})\.(.)/;
    my $lotnum = "$lot_prefix.$legacy_split";
    my ($short_station_name) = $prober =~ /^(.{4})/;
    my $platform_specific_header_data = PrbCfg::additional_header($prober, $cassette);

    if (open(DLOG_HEADER, ">$LOAD_PORT{$prober}{$cassette}{'dlog_header'}")) {
        print DLOG_HEADER "PROGRAM: $JOB_NAME\n";
        print DLOG_HEADER "LOT: $lotnum\n";
        print DLOG_HEADER "LOT_ID: $lot_id\n";
        print DLOG_HEADER "TESTER: $short_station_name\n";
        print DLOG_HEADER "STATION_NAME: $prober\n";
        print DLOG_HEADER "FAB: $PRB_LOT_ATTR{$lot_id}{$lot_id}{'ORIGIN FACILITY NO'}\n";
        print DLOG_HEADER "DESIGN_ID: $PRB_LOT_ATTR{$lot_id}{$lot_id}{'DESIGN_ID'}\n";
        print DLOG_HEADER "PART_TYPE: $PRB_LOT_ATTR{$lot_id}{$lot_id}{'PART'}\n";
        print DLOG_HEADER "PRB_FACILITY: $PROBE_FACILITY\n";
        print DLOG_HEADER "PROCESS_ID: $PROCESS_STEP{'pid'}\n";
        print DLOG_HEADER "WAF_SIZE: $PRB_LOT_ATTR{$lot_id}{$lot_id}{'WAFER SIZE'}\n";
        print DLOG_HEADER "OPERATOR: $OPERATOR_ID\n";
        print DLOG_HEADER "MENU_VER: $MENU_VERSION\n";
        print DLOG_HEADER "MENU_URL: $SVN_URL\n";
        print DLOG_HEADER "RUN_ID: $LOAD_PORT{$prober}{$cassette}{'run_id'}\n" if (defined $LOAD_PORT{$prober}{$cassette}{'run_id'});
        print DLOG_HEADER "INTERFACE: NA\n"; # used in back-end, required in DFS
        print DLOG_HEADER "PROBE_PROGRAM_KEY: $PRB_LOT_ATTR{$lot_id}{$lot_id}{'PROBE PROGRAM KEY'}\n";
        
        my $config_bit = $PCARD_DATA{$prober}{'bit_config_id'};
        if (!$NO_PROBECARD) {
            print DLOG_HEADER "PRB_CARD: $PCARD_ID{$prober}\n";
            print DLOG_HEADER "PC_CONFIG_BIT: $config_bit\n";
            if (defined $PCARD_DATA{$prober}{'probe_card_type_code'} and ($PCARD_DATA{$prober}{'probe_card_type_code'} ne '')) {
               print DLOG_HEADER "PRB_CARD_NAME: $::PCARD_DATA{$prober}{'probe_card_type_code'}\n";
            }

            if ($LOCAL_MOVE_TABLE_DIR) {
                print DLOG_HEADER "UNITS_EXPECTED: $MOVE_TABLE_INFO{$config_bit}{'total_die'}\n";
            }
            if (defined $GERM_LOT_INFO{$config_bit}{$lot_id}{'GERM_VERSION'}) { # not available if routing through MESSRV
                print DLOG_HEADER "GERM_VER: $GERM_LOT_INFO{$config_bit}{$lot_id}{'GERM_VERSION'}\n";
                print DLOG_HEADER "GERM_EQUIP_VER: $GERM_LOT_INFO{$config_bit}{$lot_id}{'process_equip_version'}\n";
                print DLOG_HEADER "GERM_DSID_VER: $GERM_LOT_INFO{$config_bit}{$lot_id}{'design_id_version'}\n";
            }
            if ($PCARD_DATA{$prober}{'child_lens_module_id'} and ($PCARD_DATA{$prober}{'child_lens_module_id'} ne 'null')) {
                print DLOG_HEADER "CARD_LENS_MODULE: $PCARD_DATA{$prober}{'child_lens_module_id'}\n";
            }
        }
        if ($::MOVE_TABLE_INFO{$config_bit}{'x_die_size_um'} and $::MOVE_TABLE_INFO{$config_bit}{'y_die_size_um'}) {
            print DLOG_HEADER "X_DIE_SIZE_UM: $::MOVE_TABLE_INFO{$config_bit}{'x_die_size_um'}\n";
            print DLOG_HEADER "Y_DIE_SIZE_UM: $::MOVE_TABLE_INFO{$config_bit}{'y_die_size_um'}\n";
            # Compute area in cm^2 per engineering.
            my $die_area_cm2 = ($::MOVE_TABLE_INFO{$config_bit}{'x_die_size_um'} * $::MOVE_TABLE_INFO{$config_bit}{'y_die_size_um'})/100000000;
            print DLOG_HEADER sprintf("DIE_SIZE: %0.4f\n", $die_area_cm2);
        }
        if ( $MES_ATTR{$lot_id}{'FAB CONV ID'} and ($MES_ATTR{$lot_id}{'FAB CONV ID'}[0] ne '') ) {
           print DLOG_HEADER "FAB_CONV_ID: $MES_ATTR{$lot_id}{'FAB CONV ID'}[0]\n";
        }
        if ( $MES_ATTR{$lot_id}{'RETICLE WAVE ID'} and ($MES_ATTR{$lot_id}{'RETICLE WAVE ID'}[0] ne '') ) {
           print DLOG_HEADER "RETICLE_WAVE_ID: $MES_ATTR{$lot_id}{'RETICLE WAVE ID'}[0]\n";
        }
        if ($platform_specific_header_data) {
            print DLOG_HEADER $platform_specific_header_data;
        }
        close DLOG_HEADER;
        return(undef);
    } else {
        return(PrbLocale::file_open_fail($LOAD_PORT{$prober}{$cassette}{'dlog_header'}, 'write', $!));
    }
}

###############################################################################
# Description:
#     logs setup information that can be used for reporting
# Returns:
#     nothing
# Globals:
#     $SCRIPT_FILE, $SCRIPT_EXT, $OPERATOR_ID, $TESTER_ID, $JOB_NAME,
#     $GERM_PROCESS, $GERM_RECIPE, $MOVE_TABLE, $OVERRIDE_REASON
#     %LOAD_PORT, %PCARD_ID, %PROCESS_STEP, %OVERRIDE, %OPT, %TIMING_STATS
#     @GERM_EXCEPTION_NAMES
###############################################################################
sub record_setup_information {
    my ($setup_cancel) = @_;
    my $epoch = time();
    my $run_options =
        "${SCRIPT_FILE}${SCRIPT_EXT} -equip_id=$TESTER_ID" .
        " -site=$OPT{'site'} -epoch=$epoch";
    if ($setup_cancel) {
        $run_options .= " -CANCEL='$setup_cancel'";
    }
    if ($OPERATOR_ID) {
        $run_options .= " -oper=$OPERATOR_ID";
    }
    if ($JOB_NAME) {
        $run_options .= " -job=$JOB_NAME";
    }
    if ($PROCESS_STEP{'pid'}) {
        $run_options .= " -pid=$PROCESS_STEP{'pid'}";
        if ($OPT{'pid_germ'} and !$OVERRIDE_REASON and ($RECIPE{'PID'} !~ /$PROCESS_STEP{'pid'}/i)) {
            $run_options .= " -overwritten_pid=$RECIPE{'PID'}";
        }
    }
    if ($GERM_PROCESS) {
        $run_options .= " -process='$GERM_PROCESS'";
    }
    if ($GERM_RECIPE) {
        $run_options .= " -recipe='$GERM_RECIPE'";
    }
    if ($TEMPERATURE) {
        $run_options .= " -temp=$TEMPERATURE";
    }
    if (@GERM_EXCEPTION_NAMES) {
        $run_options .= " -exception='@GERM_EXCEPTION_NAMES'";
    }
    my %setup_prober; # to record cardID
    foreach my $prober (keys %LOAD_PORT) {
        foreach my $cassette (keys %{$LOAD_PORT{$prober}}) {
            if (($LOAD_PORT{$prober}{$cassette}{'status'} eq 'available') and
                 $LOAD_PORT{$prober}{$cassette}{'lot_id'}) {
                $setup_prober{$prober} = prober_alpha_designator($prober);
                $run_options .= " -${cassette}$setup_prober{$prober}=$LOAD_PORT{$prober}{$cassette}{'lot_id'}";
                if ($LOAD_PORT{$prober}{$cassette}{'batch_id'}) {
                    $run_options .= " -batch$setup_prober{$prober}=$LOAD_PORT{$prober}{$cassette}{'batch_id'}";
                }
            }
        }
    }
    foreach my $prober (keys %setup_prober) {
        if ($PCARD_ID{$prober}) {
            $run_options .= " -card$setup_prober{$prober}=$PCARD_ID{$prober}";
        }
    }
    if ($OVERRIDE_REASON) {
        $run_options .= " -override -reason='$OVERRIDE_REASON'";
    }
    if ($NEW_TEST_JOB_MSG and defined $UPDATE_TEST_JOB) {
        $run_options .= " -update_job=$UPDATE_TEST_JOB";
    }
    if ($NEW_MOVE_TABLE_MSG and defined $UPDATE_MOVE_TABLE) {
        $run_options .= " -update_mtable=$UPDATE_MOVE_TABLE";
    }
    if ($PROBE_ON_HOLD) {
        $run_options .= " -onhold=$PROBE_ON_HOLD";
    }
    if ($SCRAPPED_WAFERS) {
        $run_options .= " -scrapped=$PROBE_SCRAPPED";
    }
    if ($MOVE_TABLE) {
        $run_options .= " -move_table=$MOVE_TABLE";
    }
    if ($REQUEST) {
        $run_options .= " -request='$REQUEST'";
    }
    notify('log', $run_options);
    my $timing_message = "TIMING";
    foreach my $event_name (keys %TIMING_STATS) {
        if (defined $TIMING_STATS{$event_name}{'elapsed'}) {
            $timing_message .= " -${event_name}=$TIMING_STATS{$event_name}{'elapsed'}";
        }
    }
    notify('log', $timing_message);
}

###############################################################################
# Description:
#     performs post lot processing start actions
#     Change Card State in ET
# Returns:
#     nothing
# Globals:
#     %LOAD_PORT
###############################################################################
sub post_start_actions {
    if (!$OPT{'offline'} and !$NO_PROBECARD) {
        time_it('start_card');
        foreach my $prober (keys %LOAD_PORT) {
            foreach my $cassette (keys %{$LOAD_PORT{$prober}}) {
                if (($LOAD_PORT{$prober}{$cassette}{'status'} eq 'available') and
                     $LOAD_PORT{$prober}{$cassette}{'lot_id'}) {
                    my $lot_id = $LOAD_PORT{$prober}{$cassette}{'lot_id'};
                    my $bond_pad_from_attribute = $MES_ATTR{$lot_id}{'CU BOND PAD TYPE'}[0] ? $MES_ATTR{$lot_id}{'CU BOND PAD TYPE'}[0] : 'MISSING';
                    my $lookup_bond_pad_material = GetContamType($bond_pad_from_attribute);
                    my $pct_subject;
                    my $msg;
                    if (defined $PCTSRVXML and $PCTSRVXML) {                
                        $msg = sprintf  "<PCT_START_CARD>".
                                            "<Input>" .
                                                "<EquipId>$prober</EquipId>" .
                                                "<ProbeCardId>PC-%06d</ProbeCardId>".
                                                "<Devl>NO</Devl>".     #'NO' (default) tells PCT to use the production database.
                                                                        #'YES' tells PCT to use the development database.
                                                "<Mode>PROD</Mode>".    #'TEST' tells PCT to not update the card status
                                                                        #'PROD' (default) tells PCT to update the status                                                
                                                ($lookup_bond_pad_material?"<ContamType>$lookup_bond_pad_material</ContamType>":"") .
                                            "</Input>".
                                        "</PCT_START_CARD>",                                        
                                        $PCARD_ID{$prober};  
                        $pct_subject = $PCTSRVXML;
                    } else {
                        # deprecated
                        $msg = sprintf "PCT_START_CARD PROBECARD_ID='PC-%06d' EQUIP_ID='$prober' SITE_NAME='$OPT{'site'}'",$PCARD_ID{$prober};
                        $msg .= " CONTAM_TYPE='$lookup_bond_pad_material'" if $lookup_bond_pad_material;
                        $pct_subject = $PCTSRV;
                    }
#                    print $msg."\n";
                    my ($status, $reply) = send_receive_mipc($OPT{'site'}, $pct_subject, $msg);
#                    print $reply."\n";
                }
            }
        }
        time_it('start_card', 'end');
    }
    return(undef);
}

#----------------------------------------------------------------------------
# Subroutine: fix_keypad
#
# Override keypress bindings so that Sun keypads work properly.
# taken verbatim from existing Perl Menu
# then modified to handle Return and Keypad Enter
#----------------------------------------------------------------------------
sub fix_keypad {
   my ($widget) = @_;

   $widget->bind('<KeyPress>' =>
      sub {
         my $e = $_[0]->XEvent;
         # for debug
#         print "keysym=" . $e->K . " numeric=" . $e->N . " A=" . $e->A . "\n";
         if ($e->A eq '4' and $e->K eq 'Left') {
            $_[0]->eventGenerate('<KeyPress>', -keysym => '4' );
            Tk->break;
         }
         elsif ($e->A eq '6' and $e->K eq 'Right') {
            $_[0]->eventGenerate('<KeyPress>', -keysym => '6' );
            Tk->break;
         }
         elsif ($e->A eq '.' and $e->K eq 'Delete') {
            $_[0]->eventGenerate('<KeyPress>', -keysym => 'period' );
            Tk->break;
         }
         elsif (($e->K eq 'KP_Enter') or ($e->K eq 'Return')) {
            $widget->focusNext;
         }
      }
   );
# could be used instead of KeyPress binding
#   $widget->bind('<Return>' => sub {$widget->focusNext;});
   $widget->bindtags([$widget,ref($widget),$widget->toplevel,'all']);
}

###############################################################################
# Description:
#     gather timing statistics
# Returns:
#     nothing
# Globals:
#     %TIMING_STATS
###############################################################################
sub time_it {
    my ($event_name, $event_type) = @_;
    $event_type = 'start' unless $event_type;
    # could switch to HiRes, but I don't think that is needed
    $TIMING_STATS{$event_name}{$event_type} = time();
    if (($event_type ne 'start') and $TIMING_STATS{$event_name}{'start'}) {
        $TIMING_STATS{$event_name}{'elapsed'} += $TIMING_STATS{$event_name}{$event_type} - $TIMING_STATS{$event_name}{'start'};
    }
}

###############################################################################
# Description:
#     determine if a given Data Collection Process ID is valid
#     and if so, return a Probe Tracking Step valid for that Process ID
# Returns:
#     nothing
# Globals:
#     %PROCESS_LIST
###############################################################################
sub lookup_tracking_step {
    my ($pid_key, $current_step) = @_;
    # check the current step first, if the pid_key is valid, this should be the correct step
    if ($PROCESS_LIST{$current_step}{$pid_key}) {
        return($current_step);
    } else {
        foreach my $FabStepName (keys %PROCESS_LIST) {
            foreach my $ProcessId (keys %{$PROCESS_LIST{$FabStepName}}) {
                if ($ProcessId eq $pid_key) {
                    return($FabStepName);
                }
            }
        }
        return(undef);
    }
}

###############################################################################
# Description:
#     determine if a batch exists for the specified lot(s)
#     performs some batch validation
#     if the lot is not provided the batches will be retrieved by equip_id
# Returns:
#     $status       - non-zero value for error
#     $attr_ref     - lot attributes
#     $meta_ref     - lot tracking information
#     $recipe_param - GeRM recipe parameters
#     $recipe_meta  - GeRM information
#     $batch_meta   - other information about the batch
# Globals:
#     ???
###############################################################################
sub get_batch_information {
    my ($lot_id) = @_;
    my $any_error;  # localized error message
    time_it('get_batch');
    my $soapBody = "<BatchRetrieve>" .
                       "<Input>";
    if ($lot_id) {
        $soapBody .=
                           "<LotId>$lot_id</LotId>";
    } else {
        $soapBody .=
                           "<EquipId>$TESTER_ID</EquipId>";
    }
    $soapBody .=
                       "</Input>" .
                   "</BatchRetrieve>";
    my ($status, $reply) = send_receive_mipc_soap($OPT{'site'}, $MESSRV, $soapBody);
    time_it('get_batch', 'end');
    if ($status)
    {
        return($reply, undef, undef, undef, undef);
    }
    else
    {
        my ($parse_status, $attr_ref, $meta_ref, $recipe_param, $recipe_meta, $batch_meta) = parse_batch_stage_controller_response($reply);
        if ($parse_status) {
            return($parse_status, undef, undef, undef, undef, undef);
        } else {
            return(undef, $attr_ref, $meta_ref, $recipe_param, $recipe_meta, $batch_meta);
        }
    }
}

###############################################################################
# Description:
#     Updates wafers that will be processed
#     Obtains Process RunID
#     Commits the lot in Probe Tracking, updates Lot State in MES,
#     updates MES Lot Attributes,
#     and Stages the Lot in ET as applicable
# Input:
#     $eng_debug - non-zero for engineering debug setip
# Returns:
#     $status    - non-zero value for error
# Globals:
#     $JOB_NAME, $BSC_MODE, $GERM_PROCESS, $GERM_RECIPE, %MES_META, %PROCESS_LIST
#     %LOAD_PORT, %PROCESS_STEP, %SITE_CFG, %OPT, %CARRIER_USER_COPY
#     output:
#     %PRB_PROCESS_STATE
#     input, output:
#     %RECIPE,
#
###############################################################################
sub commit_batches {
    my ($eng_debug) = @_;
    my $any_error;
    my $stage_to_eta = (!$OPT{'offline'} and !$BSC_MODE and !$OPT{'nostage'} and $PrbCfg::PlatformCfg{'EtaScript'}) ? 1 : 0;
    my %attr_list;
    $attr_list{$PRB_GERM_PROCESS_CORR_ITEM} = $GERM_PROCESS ? $GERM_PROCESS : '';
    $attr_list{$PRB_GERM_RECIPE_CORR_ITEM} = $GERM_RECIPE ? $GERM_RECIPE : '';
    $attr_list{$PRB_JOB_GERM_NAME_CORR_ITEM} = $JOB_NAME ? $JOB_NAME : '';
    my $local_job_rev = PrbCfg::get_job_rev($JOB_NAME);
    $attr_list{$PRB_JOB_GERM_REV_CORR_ITEM} = $local_job_rev ? $local_job_rev : '';
    notify('log', "commit_batches() GERM_RECIPE=$attr_list{$PRB_GERM_PROCESS_CORR_ITEM} JOB_NAME=$JOB_NAME local_job_rev=$attr_list{$PRB_JOB_GERM_REV_CORR_ITEM}");

    foreach my $prober (keys %LOAD_PORT) {
        foreach my $cassette (keys %{$LOAD_PORT{$prober}}) {
            if (($LOAD_PORT{$prober}{$cassette}{'status'} eq 'available') and
                 $LOAD_PORT{$prober}{$cassette}{'lot_id'}) {
                my $lot_id = $LOAD_PORT{$prober}{$cassette}{'lot_id'};
                my $scribe_list;        # comma separated list of scribes that will be processed
                # for 'independent' lots the config file is currently responsible for setting 'process_id' and 'job_name'
                my $process_id = $OPT{'independent'} ? $LOAD_PORT{$prober}{$cassette}{'process_id'} : $PROCESS_STEP{'pid'};
                my $job_to_run = $OPT{'independent'} ? $LOAD_PORT{$prober}{$cassette}{'job_name'} : $JOB_NAME;
                my $wafers_removed = 0;
                my $wafers_added = 0;
                foreach my $slot_num (sort {$a<=>$b} keys %{$LOAD_PORT{$prober}{$cassette}{'carrier'}}) {
                    if ($CARRIER_USER_COPY{$prober}{$cassette}{$slot_num}{'WaferState'}) {
                        my $wafer_scribe = $CARRIER_USER_COPY{$prober}{$cassette}{$slot_num}{'WaferScribe'};
                        if ($CARRIER_USER_COPY{$prober}{$cassette}{$slot_num}{'WaferState'} =~ /Committed/i) {
                            $scribe_list .= "," if $scribe_list;
                            $scribe_list .= $wafer_scribe;
                            if ($LOAD_PORT{$prober}{$cassette}{'carrier'}{$slot_num}{'WaferState'} !~ /Committed/i) {
                                $wafers_added = 1;
                            }
                        } else {
                            if ($LOAD_PORT{$prober}{$cassette}{'carrier'}{$slot_num}{'WaferState'} =~ /Committed/i) {
                                $wafers_removed = 1;
                            }
                        }
                    } elsif ($LOAD_PORT{$prober}{$cassette}{'carrier'}{$slot_num}{'WaferState'} and ($LOAD_PORT{$prober}{$cassette}{'carrier'}{$slot_num}{'WaferState'} =~ /Committed/i)) {
                        $wafers_removed = 1;
                    }
                }
                # for 'independent' lots there currently is no way to change PID
                my $data_collect_mode_changed = ($OPT{'pid_germ'} and !$OVERRIDE_REASON and !$OPT{'independent'} and ($RECIPE{'PID'} !~ /$process_id/i)) ? 1 : 0;
                my $commit_batch_to_mes = (!$eng_debug and $BSC_MODE and (!$wafers_removed or $OPT{'alter_batch_ok'}) and !$data_collect_mode_changed) ? 1 : 0;
                my $commit_to_probe_tracking = (!$eng_debug);
                if ($OPT{'partial_commit'} and !$BSC_MODE) {
                    # MJP only wants to send ProcessCommit in $BSC_MODE or when running a Production PID
                    # this violates requirement in ISTRK02898745
                    my $apparent_step = lookup_tracking_step($process_id, $MES_META{$lot_id}{'StepName'});
                    if ($apparent_step and ($PROCESS_LIST{$apparent_step}{$process_id}{'ModeDesc'} !~ /PRODUCTION/i)) {
                        $commit_to_probe_tracking = 0;
                    }
                }
                if (!$scribe_list) {
                    $any_error .= "\n" if $any_error;
                    $any_error .= PrbLocale::no_wafers_selected($lot_id, $process_id);
                } elsif ($commit_to_probe_tracking) {
                    my $platform_job_list;
                    eval { # optional PrbCfg subroutine that can be used to assign different job for every wafer
                        $platform_job_list = PrbCfg::pre_commit_check($lot_id, $prober, $process_id, $LOAD_PORT{$prober}{$cassette}{'run_id'}, $scribe_list, $job_to_run);
                    };
                    if ($@ and ($@ !~ /Undefined subroutine/i)) {
                        return($@);
                    } elsif ($platform_job_list) {
                        $job_to_run = $platform_job_list;
                    }
                    my $run_id = $LOAD_PORT{$prober}{$cassette}{'run_id'};
                    my ($status, $ptrack_run_id, $process_state_ref) = send_probe_process_commit($lot_id, $prober, $process_id, $run_id, $scribe_list, $job_to_run);
                    if ($status) {
                        $any_error .= "\n" if $any_error;
                        $any_error = $status;
                    } elsif (($status) = set_mes_attributes($lot_id, 1, %attr_list)) {
                        $any_error .= "\n" if $any_error;
                        $any_error = $status;
                    } elsif (!$OPT{'offline'}) {
                        %{$PRB_PROCESS_STATE{$lot_id}{$process_id}{$run_id}} = %{$process_state_ref};
                    }
                }
                if (!$any_error and $commit_batch_to_mes and $LOAD_PORT{$prober}{$cassette}{'batch_id'} and ($LOAD_PORT{$prober}{$cassette}{'batch_state'} !~ /Running/i)) {
                    my $batch_id = $LOAD_PORT{$prober}{$cassette}{'batch_id'};
                    my $staged_to_equip = $LOAD_PORT{$prober}{$cassette}{'staged_to'};
                    my ($update_lot_status) = update_lot_state($lot_id, $batch_id, 'Committed', $staged_to_equip);
                    if ($update_lot_status) {
                        $any_error .= "\n" if $any_error;
                        $any_error .= $update_lot_status;
                    }
                }
                if (!$any_error and !$commit_batch_to_mes and $LOAD_PORT{$prober}{$cassette}{'batch_id'}) {
                    # it is likely the expected batch was altered, either wafers were removed, Data Collection Mode was changed
                    # or this is a eng_debug run.  Clear the batch_id so the lot will not Track-Out at completion
                    notify('log', "Removing BatchId=$LOAD_PORT{$prober}{$cassette}{'batch_id'} for Lot=$lot_id Prober=$prober Cassette=$cassette to prevent auto-tracking");
                    delete $LOAD_PORT{$prober}{$cassette}{'batch_id'};
                }
                if (!$any_error and $stage_to_eta) {
                    # if the lot is staged in MES, this is not needed, however if the lot is not staged this enables ET Run State Transitions
                    # it would be better to fail if we can't stage the lot
                    my $chamber_id = uc prober_alpha_designator($prober);
                    my $lot_type = $eng_debug ? 'NONPROD' : 'PROD';
                    system (@{$PrbCfg::PlatformCfg{'EtaScript'}}, "-log=STAGE", "-equip_id=$TESTER_ID", "-chamber_id=$chamber_id", "-lot_id=$lot_id", "-lot_type=$lot_type");
                }
                my $lot_comment;
                if (!$any_error and ($MES_META{$lot_id}{'StateDesc'} =~ /Hold/i)) {
                    $lot_comment = "Probing while lot is on hold";
                } elsif (!$any_error and $OVERRIDE_REASON) {
                    $lot_comment = "Probing in Override mode";
                } elsif (!$any_error and $OPT{'process_type'} and $EQUIP_STATE_ALLOW{'process_run'} and $ENGR_REQUEST) {
                    # consider refactoring
                    $lot_comment = "Probing $OPT{'process_type'} ProcessRecipe '$ENGR_REQUEST'";
                }
                # CQ-ISTRK03201023 add lot comment for reprobes
                if (!$any_error and $LOAD_PORT{$prober}{$cassette}{'reprobe'}) {
                    $lot_comment = "Some wafers are being re-probed" unless $lot_comment;
                }
                if ($lot_comment) {
                    my $equipment_state = $NO_CHILD_EQUIPMENT ? $ET_STATE{$TESTER_ID}{'state'} : $ET_STATE{$TESTER_ID}{'child'}{$prober}{'state'};
                    $lot_comment .= " - Equipment='$prober'; ETState='$equipment_state'; TestJob='$job_to_run'; ProcessId='$process_id'; wafers='$scribe_list'";
                    $lot_comment .= "; ProcessMode=$PROCESS_STEP{'ModeDesc'}" if $PROCESS_STEP{'ModeDesc'};
                    $lot_comment .= "; Reason='$OVERRIDE_REASON'" if $OVERRIDE_REASON;
                    my $add_comment_status = add_lot_comment($lot_id, $EMPLOYEE_NAME, $lot_comment);
                    if ($add_comment_status) {
                        $any_error .= "\n" if $any_error;
                        $any_error .= $add_comment_status;
                    }
                }
                if (!$any_error) {
                    # update the carrier with user changes if applicable
                    %{$LOAD_PORT{$prober}{$cassette}{'carrier'}} = %{$CARRIER_USER_COPY{$prober}{$cassette}};
                }
            } # if introducing lot_id
        } # foreach $cassette
    } # foreach $prober
    notify('debug', Data::Dumper->Dump([\%PRB_PROCESS_STATE], [qw(*PRB_PROCESS_STATE)]));
    notify('debug', Data::Dumper->Dump([\%LOAD_PORT], [qw(*LOAD_PORT)]));
    return($any_error);
}

###############################################################################
# Description:
#     Sends ProcessCommit to Probe Tracking and parses response
# Input:
#    $facility   - Manufacturing Site - Example: 'BOISE' or $ENV{'SITE_NAME'}
#    $lot_id     - Valid Micron lot number in 1234567.111 format
#    $equip      - should be the prober ID or mainframe
#    $pid        - Process ID
#    $runid      - RunID or undef
#    $scribe_csv - list of wafers to process
#    $job_name   - RequestedProgramName, may be a list of programs for param
#    @trk_srvs   - one or more tracking servers
# Returns:
#     $status    - localized error message on failure
#     $run_id    - assigned by Probe Tracking ?????????
#     /%process_states - Process States assigned by Probe Tracking
# Globals:
#     $JOB_NAME, $BSC_MODE
#     %LOAD_PORT, %PROCESS_STEP, %SITE_CFG, %OPT, %CARRIER_USER_COPY
#     output:
#     %PRB_PROCESS_STATE
#     input, output:
#     %RECIPE,
#
###############################################################################
sub send_probe_process_commit {
    my ($lot_id, $equip, $process_id, $run_id, $scribe_list, $job_to_run) = @_;
    if ($OPT{'offline'}) {
        notify('debug', "OFFLINE_MESSAGE_NOT_SENT ProbeProcessCommit lot=$lot_id equip=$equip process_id=$process_id run_id=$run_id scribe_list=$scribe_list job_to_run=$job_to_run");
        return(undef);
    }
    my ($status, $reply) = ProbeProcessCommit($OPT{'site'}, $lot_id, $equip, $process_id, $run_id, $scribe_list, $job_to_run, @{$SITE_CFG{'PrbTrack'}{$OPT{'site'}}});
    if ($status) {
        return(PrbLocale::ptrack_error($lot_id, $status), undef, undef);
    } else {
        my ($output_section, $wafer_id, $wafer_scribe, $process_id, $run_id, $exception, $soap_fault, $soap_exception);
        my %process_states;
        my $xp = XML::Parser->new(
            Style     => 'Stream',
            Handlers  => {
                Char  => sub {
                    my ($expat, $string) = @_;
                    if ($output_section and $wafer_scribe) {
                       $process_states{$wafer_scribe}{$expat->current_element} = $string;
                    } elsif ($exception) {
                        if ($expat->current_element =~ /Text$/) {
                            $soap_exception .= "\n" if $soap_exception;
                            $soap_exception .= $string;
                        }
                    } elsif ($soap_fault) {
                        if ($expat->current_element =~ /detail/i) {
                            $soap_exception .= "\n" if $soap_exception;
                            $soap_exception .= $string;
                        }
                    }
                },
                Start => sub {
                    my ($expat, $element, %attrs) = @_;
                    if ($element =~ m/^OutputSection$/) {
                        $output_section = 1;
                    } elsif ($element =~ m/^Wafer$/) {
                        $wafer_id = $attrs{'WaferId'};
                        $wafer_scribe = $attrs{'WaferScribeId'};
                    } elsif ($element =~ m/^Process$/) {
                        $process_id = $attrs{'ProcessId'};
                        $run_id = $attrs{'RunId'} if $attrs{'RunId'};
                    } elsif ($element =~ m/^ExceptionSection$/) {
                        # Tracking Server uses this element to display errors
                        $exception = 1;
                    } elsif ($element =~ m/^SOAP-ENV:Fault$/) {
                        # baserv will throw a SOAP-ENV:Fault
                        $soap_fault = 1;
                    }
                },
                End   => sub {
                    my ($expat, $element, %attrs) = @_;
                    if ($element =~ m/^OutputSection$/) {
                        $output_section = 0;
                    } elsif ($element =~ m/^Wafer$/) {
                        $wafer_id = undef;
                        $wafer_scribe = undef;
                    } elsif ($element =~ m/^Process$/) {
                        # do nothing we need $process_id and $run_id
                    } elsif ($element =~ m/^ExceptionSection$/) {
                        $exception = 0;
                    } elsif ($element =~ m/^SOAP-ENV:Fault$/) {
                        $soap_fault = 0;
                    }
                },
            },
        )->parse($reply);
        if ($soap_exception) {
            return(PrbLocale::ptrack_error($lot_id, $soap_exception), undef, undef);
        } else {
            return(undef, $run_id, \%process_states);
        }
    }
}

###############################################################################
# Description:
#     Notifies MESSRV of important lot state changes, see
# http://cfgenprod.micron.com/webapps/mfg/MESAutoInt/documentation/details/LotUpdate.xml
# Returns:
# Globals:
#     $TESTER_ID
###############################################################################
sub update_lot_state {
    my ($lot_id, $batch_id, $state, $staged_to_equip, $abort_code, $abort_reason) = @_;
    my $soapBody = "<LotUpdate>" .
                       "<Input>" .
                          "<Batch>" .
                             "<BatchId>$batch_id</BatchId>" .
                             "<SchedState>$state</SchedState>" .
                          "</Batch>" .
                          "<Equip>" .
                             "<EquipId>$TESTER_ID</EquipId>";
    if ($staged_to_equip !~ $TESTER_ID) {
        my $chamber_id = uc prober_alpha_designator($staged_to_equip);
        $soapBody .=
                             "<ChamberList>" .
                                "<Chamber>" .
                                   "<ChamberId>$chamber_id</ChamberId>" .
                                "</Chamber>" .
                             "</ChamberList>";
    }
    $soapBody .=
                          "</Equip>";
    if ($abort_code and $abort_reason) {
        $soapBody .=
                          "<AbortCode>$abort_code</AbortCode>" .
                          "<AbortReason>$abort_reason</AbortReason>";
    }
    $soapBody .=
                       "</Input>" .
                   "</LotUpdate>";
    if ($OPT{'offline'}) {
        notify('debug', "OFFLINE_MESSAGE_NOT_SENT $soapBody");
        return(undef);
    }
    notify('log', "Sending LotUpdate SchedState=$state for LotId=$lot_id BatchId=$batch_id");
    time_it('lot_update');
    my ($status, $reply) = send_receive_mipc_soap($OPT{'site'}, $MESSRV, $soapBody);
    time_it('lot_update', 'end');
    if ($status)
    {
        return(PrbLocale::lot_commit_error($lot_id, $reply));
    }
    else
    {
        my $soap_error = check_for_soap_error($reply);
        if ($soap_error) {
            return(PrbLocale::lot_commit_error($lot_id, $soap_error));
        }
    }
    return(undef);
}

###############################################################################
# Description:
#     determine if the response from a SOAP command contains an error
#     this method should work for most command sent to MESSRV for MES TRacking
# Returns:
#     undef - success
#     SOAP-ENV:Fault StatusDetail node for failure
#     Note: there may be a bug here, I am excluding StatusDetail, which means
#           I will return things like StatusText
###############################################################################
sub check_for_soap_error {
    my ($soap_reply) = @_;
    my $any_error;   # error text from the SOAP response
    my $soap_fault;  # flag indicating a SOAP-ENV:Fault was detected
    my $xp = XML::Parser->new(
        Style     => 'Stream',
        Handlers  => {
            Char  => sub {
                my ($expat, $string) = @_;
                if ($soap_fault) {
                    if ($expat->current_element !~ m/^StatusDetail$/) {
                        $any_error .= "\n" if $any_error;
                        $any_error .= $string;
                    }
                }
            },
            Start => sub {
                my ($expat, $element, %attrs) = @_;
                if ($element =~ m/^SOAP-ENV:Fault$/) {
                    $soap_fault = 1;
                }
            },
            End   => sub {
                my ($expat, $element, %attrs) = @_;
                if ($element =~ m/^SOAP-ENV:Fault$/) {
                    $soap_fault = 0;
                }
            },
        },
    )->parse($soap_reply);
    return($any_error);
}

###############################################################################
# Description:
#     obtains a list of Processes from GeRM
#
# Input:
#     $process_type - Archived, Deviation, NonProduct, Product,
#                     Qual, SubRecipe, VirtualCDM
# Returns:
#     $status       - 0 or undef : success
#                     non-zero indicates fail
#     @process_list - a list of processes
###############################################################################
sub get_process_list {
    my ($process_type) = @_;
    time_it('get_process_list');
    my $soapBody =
        "<ProcessList>" .
            "<Input>" .
                "<EquipId>$TESTER_ID</EquipId>" .
                "<ProcessType>$process_type</ProcessType>" .
                "<FacilityId>$SITE_CFG{'GeRMFacility'}{$OPT{'site'}}</FacilityId>" .
            "</Input>" .
        "</ProcessList>";
    my ($status, $reply) = send_receive_mipc_soap($OPT{'site'}, $MESSRV, $soapBody);
    time_it('get_process_list', 'end');
    if ($status)
    {
        return($reply, undef);
    }
    else
    {
        my ($parse_status, @process_list) = parse_process_response($reply);
        if ($parse_status) {
            return($parse_status, undef);
        } else {
            return(undef, @process_list);
        }
    }
}

###############################################################################
# Description:
#     parses the ProcessList response from GeRM
# Returns:
#     $status       - 0 or undef : success
#                     non-zero indicates fail (not localized)
#     @process_list - a list of processes
###############################################################################
sub parse_process_response {
    my ($xml_data) = @_;
    my @process_list;
    my $any_error;   # error text from the SOAP response
    my $xp = XML::Parser->new(
        Style     => 'Stream',
        Handlers  => {
            Char  => sub {
                my ($expat, $string) = @_;
                if ($expat->current_element =~ m/^StatusText$/) {
                        $any_error .= "\n" if $any_error;
                        $any_error .= $string;
                } elsif ($expat->current_element =~ m/^Name$/) {
                    push @process_list, $string;
                }
            },
            Start => sub {
                # do nothing, required to avoid default handler
            },
            End   => sub {
                # do nothing, required to avoid default handler
            },
        },
    )->parse($xml_data);
    if ($any_error) {
        return($any_error, undef);
    } else {
        return(undef, @process_list);
    }
}

###############################################################################
# Description:
#     Abort any batches that are no longer on this equipment, but are in a
#     running state
# Returns:
#     nothing - errors are logged
# Globals:
#     %BATCH_LIST
###############################################################################
sub cleanup_orphaned_batches {
    my (@excludes) = @_;
    notify('debug', Data::Dumper->Dump([\%BATCH_LIST], [qw(*BATCH_LIST)]));
    foreach my $lot_id (keys %BATCH_LIST) {
        if ((!grep /$lot_id/, @excludes) and ($BATCH_LIST{$lot_id}{'SchedState'} =~ /Running/i)) {
            foreach my $staged_to_equip (@{$BATCH_LIST{$lot_id}{'Equipment'}}) {
                my ($update_lot_status) = update_lot_state($lot_id, $BATCH_LIST{$lot_id}{'BatchId'}, 'Aborted', $staged_to_equip, 999, "$SCRIPT_FILE on $TESTER_ID detected lot in a Running State");
                if ($update_lot_status) {
                    notify('log', "cleanup_orphaned_batches failed for LotId=$lot_id: $update_lot_status");
                } else { # assume it worked
                    $BATCH_LIST{$lot_id}{'SchedState'} = 'Aborted';
                }
            }
        }
    }
}

###############################################################################
# Description:
#     restrict entry value to items that are contained in the BrowseEntry List
# Returns:
#     nothing
# Globals:
#     none
###############################################################################
sub BrowseEntryKeyHandler {
    my ($self, $widget_key, $key_ascii, $key_sym, $option_ref) = @_;
    if (($key_sym eq 'KP_Enter') or ($key_sym eq 'Return')) {
        AutoCompleteBrowseEntry($self, $widget_key, $option_ref);
        eval {
            # undocumented
            $W{$widget_key}->Popdown();
        };
        $W{$widget_key}->focusNext;
    } else {
        if (SearchActivateBrowseEntry($self, $widget_key, ${$option_ref})) {
            # string typed so far is valid - nothing to do
        } else {
            if (SearchActivateBrowseEntry($self, $widget_key, $key_ascii)) {
                # last key typed is valid
                ${$option_ref} = $key_ascii;
            } else {
                ${$option_ref} = '';
            }
        }
    }
}

###############################################################################
# Description:
#     clears current BrowseEntry selection and background colors
# Returns:
#     BrowseEntry list item that matches (case insensitive) the entry value
# Globals:
#     %W
###############################################################################
sub SearchActivateBrowseEntry {
    my ($self, $widget_key, $search) = @_;
    return(undef) unless $search;
    my $found;
    my $slistbox = $W{$widget_key}->Subwidget('slistbox');
    my $reallistbox = $slistbox->Subwidget('listbox');
    my (@options) = $W{$widget_key}->cget(-choices); # older Tk does not support choices method
    my $num_items = scalar @options;
    for (my $array_index = 0; $array_index < $num_items; ++$array_index) {
        if ($options[$array_index] =~ m/^$search/i) {
            $found = $options[$array_index];
            ClearBrowseEntrySelection($widget_key);
            $W{'persist'}{$widget_key} = $array_index;
            $slistbox->activate($array_index);
            $slistbox->see($array_index);
            if (!$OLD_BROWSE_ENTRY) {
                my $entry_widget = $W{$widget_key}->Subwidget('entry');
                my $select_color = $entry_widget->cget(-selectbackground);
                $slistbox->itemconfigure($W{'persist'}{$widget_key}, -background, $select_color);
            }
            last;
        }
    }
    return $found;
}

###############################################################################
# Description:
#     convenience function to allow auto complete in a BrowseEntry
# Returns:
#     nothing
# Globals:
#     none
###############################################################################
sub AutoCompleteBrowseEntry {
    my ($self, $widget_key, $option_ref) = @_;
    my $result = SearchActivateBrowseEntry($self, $widget_key, ${$option_ref});
    if ($result) {
        # auto complete selection
        ${$option_ref} = $result;
    } else {
        ${$option_ref} = '';
    }
}

###############################################################################
# Description:
#     clears current BrowseEntry selection and background colors
# Returns:
#     nothing
# Globals:
#     %W
###############################################################################
sub ClearBrowseEntrySelection {
    my ($widget_key) = @_;
    my $slistbox = $W{$widget_key}->Subwidget('slistbox');
    # deselect any current options
    $slistbox->selectionClear(0, 'end');
    # restore background for previously activated item
    if (!$OLD_BROWSE_ENTRY and defined $W{'persist'}{$widget_key}) {
        $slistbox->itemconfigure($W{'persist'}{$widget_key}, -background, $W{$widget_key}->Subwidget('entry')->cget(-background));
    }
}

###############################################################################
# Description:
#     adds a Lot Comment
# Returns:
#     localized error message for failure
# Globals:
#     $MESSRV
###############################################################################
sub add_lot_comment {
    my ($lot_id, $operator, $comment) = @_;
    my $soapBody = "<MESLotComment>" .
                       "<Input>" .
                           "<Lot>" .
                               "<LotId>$lot_id</LotId>" .
                               "<LotComment>$comment</LotComment>" .
                               "<Username>$operator</Username>" .
                           "</Lot>" .
                       "</Input>" .
                   "</MESLotComment>";
    if ($OPT{'offline'}) {
        notify('debug', "OFFLINE_MESSAGE_NOT_SENT $soapBody");
        return(undef);
    }
    my ($status, $reply) = send_receive_mipc_soap($OPT{'site'}, $MESSRV, $soapBody);
    if ($status)
    {
        return(PrbLocale::lot_comment_error($lot_id, $reply));
    }
    else
    {
        my $soap_error = check_for_soap_error($reply);
        if ($soap_error) {
            return(PrbLocale::lot_comment_error($lot_id, $soap_error));
        }
    }
    return(undef);
}

###############################################################################
# Description:
#     display error message then exit
# Returns:
#     nothing
###############################################################################
sub fatal_startup_error {
    $W{'main'} = new MainWindow() unless $W{'main'};
    $W{'main'}->withdraw();
    my $title = $PrbLocale::Msg{'title'} ? $PrbLocale::Msg{'title'} : "Error in $SCRIPT_FILE";
    $W{'main'}->messageBox(
        -title   => $title,
        -message => "@_",
        -type    => 'OK',
    );
    notify('log', "@_");
    notify('debug', "@_");
    croak "@_\n";
}

###############################################################################
# Description:
#     Determines what the PCT Contamination type is based on the given bondpad type
# Returns:
#     PCT contaminations type
# Globals:
#     NONE
###############################################################################
sub GetContamType
{
    my ($bondpad_type) = @_;
    if ($bondpad_type =~ /^MISSING$/i)
    {
        return $OPT{site} =~ /LEHI|IMFS/i ? 'COPPER' : undef;  #  LEHI Hack, all material is copper that is not NIPD.... and LMS rule will be defined to do this in the FAB.
    }
    elsif ($bondpad_type =~ /RDL$/i)
    {
        return 'RDL';
    }
    elsif ($bondpad_type =~ /^AL/i)
    {
        return 'ALUMINUM';
    }
    elsif ($bondpad_type =~ /^CU$/i)
    {
        return 'COPPER';
    }
    elsif ($bondpad_type =~ /^NI\/PD$/i)
    {
        return 'NIPD';
    }
    elsif ($bondpad_type =~ /^TITA/i)
    {
        return 'TITANIUM';
    }
    # with any luck this error will trigger invalid_bond_pad_error, and PCT maintainer will add a cleaning
    # recipe that matches the MES attribute for the bond pad material
    return $bondpad_type;
}

###############################################################################
# Description:
#     checks if the Test Job Revision is correct for interrupt recovery mode
# Returns:
#    localized error if test job revision is not correct
# Globals:
#     $JOB_NAME, %LOAD_PORT, %OPT
###############################################################################
sub check_test_job_revision {
    my $any_error;
    foreach my $prober (keys %LOAD_PORT) {
        foreach my $cassette (keys %{$LOAD_PORT{$prober}}) {
            if (($LOAD_PORT{$prober}{$cassette}{'status'} eq 'available') and
                 $LOAD_PORT{$prober}{$cassette}{'lot_id'} and defined $LOAD_PORT{$prober}{$cassette}{'previous_rev'}) {
                my $lot_id = $LOAD_PORT{$prober}{$cassette}{'lot_id'};
                my $previous_rev = $LOAD_PORT{$prober}{$cassette}{'previous_rev'};
                my $job_to_run = $OPT{'independent'} ? $LOAD_PORT{$prober}{$cassette}{'job_name'} : $JOB_NAME;
                my $local_job_rev;
                eval {
                    $local_job_rev = PrbCfg::get_job_rev($job_to_run);
                };
                if ($local_job_rev and ( $local_job_rev ne $previous_rev ) ) {
                  $any_error .= "\n" if $any_error;
                  $any_error .= PrbLocale::testrev_not_compatible($lot_id, $job_to_run, $previous_rev, $local_job_rev);
                }
            }
        }
    }
    return($any_error);
}
