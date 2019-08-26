package      ulog;
use          Exporter ();
@ISA       = qw(Exporter);
@EXPORT    = qw( beginlog exitlog datalog errorlog warnlog append_to_ulog line_to_ulog );

##############################################################################
## @ 2000-2007 Micron Technology, Inc. All Rights Reserved.
## Unpublished - all rights reserved under the copyright laws of the
## United States.
## USE OF A COPYRIGHT NOTICE IS PRECAUTIONARY ONLY AND DOES NOT IMPLY
## PUBLICATION OR DISCLOSURE.
## 
## THIS SOFTWARE CONTAINS CONFIDENTIAL INFORMATION AND TRADE SECRETS OF MICRON
## TECHNOLOGY, INC. USE, DISCLOSURE, OR REPRODUCTION IS PROHIBITED WITHOUT THE
## PRIOR EXPRESS WRITTEN PERMISSION OF MICRON TECHNOLOGY, INC.
##############################################################################
##
##  Filename: ulog.pm
##
##############################################################################
##
##  Description: This is a perl module to handle the creation and writing to
##               the /tmp/.ulog and /var/tmp/.ulog files.
##               NOTE: This file is kept in SCCS.
##               See: http://wwwte.micron.com/~tesoft/tesoft.html and search
##                    for ulog.pm.
##############################################################################
##
##  Usage:  There are five functions in this module.
##          beginlog(progname, arglist) - mandatory for use of these functions.
##                                        This function initializes the logging
##                                        functions.  Should be at the 
##                                        beginning of the program before any
##                                        other functions from this module.
##                                        If beginlog is not called before the
##                                        other functions an error message will
##                                        be displayed.  Keyword inserted in log
##                                        text is BEGIN.
##
##          datalog(textstring) - for data log purposes.  Keyword inserted in 
##                                log is DATALOG.
##
##          exitlog(textstring, exitstatus) - to handle exiting from program.
##                                            Keyword inserted in log is EXIT.
##
##          The next two functions are used to track problems in programs.
##          Using grep the data can be extracted from /tmp/.ulog.
##
##          warnlog(textstring) - Used to log warnings to log file.  Keyword
##                                inserted in log is WARNING.
##
##          errorlog(textstring) - Used to log errors to log file.  Will not
##                                 exit.  Keyword inserted in log in ERROR.
##
##  Description of usage terms:
##		progname refers to the name of the program calling beginlog.
##		arglist is the list of arguments sent into the program calling
##			beginlog.
##		teststring is a string message to be put into the log file.
##		exitstatus is the exit status that will be returned to the
##			operating system.
## 
##  Sample output from a program using all functions:
##	
##   ulog.pl
##	#!/usr/local/bin/perl -w
##	
##	use strict;
##	use ulog;
##	
##	beginlog( $0, @ARGV );
##	
##	datalog("This is a test of datalogging.");
##	warnlog("This is a warning");
##	errorlog("This is an error");
##	
##	exitlog("Exiting program", 0);
##
##   ulog.pl arg1 arg2 arg3
##
##   /tmp/.ulog or /var/tmp/.ulog
##	925154116, BEGIN ulog.pl, arg1 arg2 arg3
##	925154116, DATALOG ulog.pl, This is a test of datalogging.
##	925154116, WARNING ulog.pl, This is a warning
##	925154116, ERROR ulog.pl, This is an error
##	925154116, EXIT ulog.pl, Exiting program, exit status 0
##
##############################################################################
##
##  Revision History:
##
##  DATE    PROGRAMMER	COMMENTS
## -------- ---------- -----------------------------------------------
## 04/23/99 TMercer	Created.
## 08/08/00 TMercer	Added check on every open and close.  Added calls to
##			umask(0).
## 09/04/01 TMercer	Added checking for the existence of the /var/tmp/log
##			directory and creation of directory if it does not
##			exist.
## 09/14/01 TMercer	Added moving of operin_errors to /var/tmp/log and 
##			creating of a link to /tmp/operin_errors.
## 09/17/01 TMercer	Added creation of /var/tmp/log/operin_errors and
##			/var/tmp/log/.ulog.
## 09/17/01 TMercer	Added moving of .ulog data from /var/tmp/.ulog to
##			/var/tmp/log/.ulog and making /var/tmp/.ulog a link
##			to /var/tmp/log/.ulog.
## 12/17/01 TMercer	Added creation of /var/tmp/log/datalog directory to
##			handle the files created by operin.
## 02/07/02 TMercer	Added POD.
## 09/17/02 TMercer	Added prototyping to exitlog() to insure a error
##			message if an argument is missing.
##			Added checking for defined variables in beginlog to
##			avoid mystry ulog.pm error messages.
## 11/28/03 TMercer	Removed all reference to operin_errors.  This file is
##			no longer used.
## 02/23/04 TMercer	Added code to reduce progmane to just the name of the
##			program for all but beginlog.  This is to help reduce
##			.ulog size.
##############################################################################
## 04/19/05 TMercer	Changed the logging from VAR_ULOG to LOG_ULOG.  
##			LOG_ULOG is where we are writing all of our ulog data
##			now.
##			Added code to allow Linux as well as Solaris in regard
##			to whether or not all of the file and directory
##			checking is done.
##			Added function append_to_ulog().  This function takes
##			a file name as an argument and will append that file
##			to the ulog with the keywords APPENDING and 
##			END_OF_APPENDING.
##############################################################################
## 02/10/06 TMercer	Added the variable $mypid and the setting of this 
##			variable to the process id in the BEGIN block for use
##			in later functions.
##			In beginlog(), exitlog(), added header.
##			In beginlog(), exitlog(), added recording of the
##			process id with "PID="
##			In exitlog(), added recording of the run time of the
##			program.
##############################################################################
## 09/14/06 TMercer	Added the backup, zipping and copy of the .ulog file 
##			to /u/summary/spooler.  This will replace other manual
##			methods of maintaining the .ulog file.
##			Added function line_to_ulog().
##			Updated POD for line_to_ulot().
##############################################################################
## 09/20/06 TMercer	Added code to deal with a zero size .ulog file when
##			checking if the .ulog file needs to be backed up.
## 09/25/06 TMercer	Changed the Thursday backup to a two day check instead
##			of a six day check.  This is to insure that more of
##			the .ulog files get backed up on Thursday.
##############################################################################
## 10/03/06 TMercer	In append_to_ulog(), changed the open statements to be
##			Perl 5.0 compliant for probe testers.
##############################################################################
## 10/05/06 TMercer	Corrected a bug in the BEGIN block that was preventing
##			the .ulog backup process from backing up .ulog.
##############################################################################
## 12/12/06 TMercer	Removed HiRes time functions.  They were not working
##			on all systems and we were not using the data.
##############################################################################
## 01/05/06 TMercer	Modified to prevent problems with backing up .ulog.
##############################################################################
## 03/09/07 TMercer	Modified BEGIN block by removing chdir() call and 
##			replacing values in system() call with variables.  The
##			chdir was causing selector to lose track of files that
##			were passed in on command line.  This was brought to 
##			my attention by MSA.
## 03/12/07 TMercer	Set the props for ulog.pm and all other files in 
##			module.
##############################################################################
## 01/18/08 TMercer     We have an occasional case where a ulog file will be
##                      created under the name of an engineer and is
##                      unwriteable to any one else.  I found a case in
##                      ulog.pm where the permissions on the file were not
##                      being set to 0666.  I have fixed this omission.
##############################################################################
##
##  Module: perl_modules
##
##  $Id: ulog.pm 3595 2008-01-18 19:33:57Z tmercer $
##  $Revision: 3595 $
##  $Date: 2008-01-18 12:33:57 -0700 (Fri, 18 Jan 2008) $
##  $Author: tmercer $
##  $HeadURL: http://svn/mfg/tesoft/control/perl_modules/trunk/ulog.pm $
##
##############################################################################


BEGIN {

   $mypid = $$;

   # Want permissions to be 666.
   umask(0);

   # initialize $progname for later checking.
   $progname = "";

   #########################################################################
   # Init filenames and checking for the .ulog directory and file structure.
   #########################################################################
   $ULOG = "/tmp/.ulog";

   $VAR_ULOG = "/var/tmp/.ulog";

   $LOG_DIR = "/var/tmp/log";

   $LOG_ULOG = "/var/tmp/log/.ulog";

   $LOG_ULOG_BAK = "/var/tmp/log/.ulog.bak";

   $LOG_ULOG_BAK_GZ = "/var/tmp/log/.ulog.bak.gz";

   $DATALOG = "/var/tmp/log/datalogging";

   # First, are we Solaris or just SunOS?
   $OSrev = `uname -r`;

   $OS = `uname`;

   if ( ( $OSrev =~ /^5/) || ( $OS =~ /Linux/i ) ) {

      ################################################
      # We need to create the LOG_DIR for future use.#
      ################################################
      if ( ! -d $LOG_DIR ) {

         if ( -e $LOG_DIR ) {

            ulink( $LOG_DIR );
         }

         mkdir( $LOG_DIR, 0777 );
      }

      if ( ! -d $DATALOG ) {

         if ( -e $DATALOG ) {

            ulink( $DATALOG );
         }

         mkdir( $DATALOG, 0777 );
      }

      ########################################
      # if LOG_ULOG does not exist create it.#
      ########################################
      if ( ! -e $LOG_ULOG ) {

         open( LOG, ">$LOG_ULOG" ) or die "Can not open $LOG_ULOG\n";

         print( LOG "\n" );

         close( LOG ) or die "Can not close $LOG_ULOG\n";

         chmod( 0666, $LOG_ULOG );
      }

      ################################################################
      # Do we have /var/tmp/.ulog?  If so, is it a link?  If not then
      # copy it's contents to /var/tmp/log/.ulog and replace it with
      # a link to /var/tmp/log/.ulog.
      ################################################################
      if ( -e $VAR_ULOG ) {

         if ( ! -l $VAR_ULOG ) {

            system( "cat $VAR_ULOG >> $LOG_ULOG" );

            unlink($VAR_ULOG);

            symlink( $LOG_ULOG, $VAR_ULOG );
         }
      }
      else {

         symlink( $LOG_ULOG, $VAR_ULOG );
      }

      ##############################################################
      # Do we have /tmp/.ulog?  If so, is it a link?  If not then
      # copy it's contents to /var/tmp/log/.ulog and replace it with
      # a link to /var/tmp/log/.ulog.
      ##############################################################
      if ( -e $ULOG ) {

         if ( ! -l $ULOG ) {

            system( "cat $ULOG >> $LOG_ULOG" );

            if ( ! unlink($ULOG) ) {

	       open( LOG, ">>$LOG_ULOG" );

	       print LOG "\n\n";
	       print LOG "ERROR: Can not unlink $ULOG\n";
	       print LOG "\n\n";

	       close( LOG );
	    }

            symlink( $LOG_ULOG, $ULOG );
         }
      }
      else {

         symlink( $LOG_ULOG, $ULOG );
      }
   }
   else {

      ############################################################
      # Since we are SunOS we only need to check for the existence
      # of /tmp/.ulog.
      ############################################################
      if ( ! -e $ULOG ) {

         open( LOG, ">$ULOG" ) or die "Can not open $ULOG\n";

         print( LOG "\n");

         close( LOG ) or die "Can not close $ULOG\n";

         chmod( 0666, $ULOG );
      }
   }

   ##############################
   ## The ulog backup code start.
   ##############################
   $tester = `uname -n`;

   chomp $tester;

   #################################
   ## When was .ulog last backed up?
   #################################
   @list = ();

   open( LOG, "<$LOG_ULOG" ) or die "Can not open $LOG_ULOG: $!\n";

   while( <LOG> ) {

      next if ( !/^\d{10}/ );

      @list = split /\s+/;

      last;
   }

   if ( @list != 0 ) {

      $logtime = $list[0];

      $logtime =~ s/\,//;

      $now = time;

      $diff = $now - $logtime;

      ########################################################################
      # If it is Thursday and .ulog is older than 2 days move it to .ulog.bak
      ########################################################################
      if ( ( ( ( localtime( time ) )[6] == 4 ) && ( $diff >= 172800 ) )
        || ( ( stat( $LOG_ULOG ) )[7] > 50000000 ) ) {

         if ( ! -e $LOG_ULOG_BAK ) {

            system "/bin/mv $LOG_ULOG $LOG_ULOG_BAK";

            open OUT, ">$LOG_ULOG" or return;

            print OUT "$now\n";

#            print OUT "$now 'ulog.pm_$Revision: 3595 $'\n" );

            close OUT;

            chmod 0666, $LOG_ULOG;
         }
      }
   }

   if ( -e $LOG_ULOG_BAK ) {

      if ( ! -e $LOG_ULOG_BAK_GZ ) {

	 if ( rename( $LOG_ULOG_BAK, "$LOG_ULOG_BAK.$$" ) ) {

            system "( /bin/nice -19 gzip $LOG_ULOG_BAK.$$ && /bin/nice -19 rsync -az --timeout=120 $LOG_ULOG_BAK.$$.gz /u/summary/spool/ulog.$tester.$$ && /bin/chmod 666 /u/summary/spool/ulog.$tester.$$ && /bin/rm -f $LOG_ULOG_BAK.$$.gz )&";
	 }
      }
   }

   if ( -e $LOG_ULOG_BAK_GZ ) {

      system "( /bin/nice -19 rsync -az --timeout=120  $LOG_ULOG_BAK_GZ /u/summary/spool/ulog.$tester.$$ && /bin/chmod 666 /u/summary/spool/ulog.$tester.$$ && /bin/rm -f $LOG_ULOG_BAK_GZ )&"
   }

   ############################
   ## The ulog backup code end.
   ############################
}


###############################################################################
## FUNCTION: beginlog( $0, @ARGV )
## AUTHOR:   TMercer
## RECEIVES: Scalar and list
## RETURNS:  Nothing.
## PURPOSE:  To collect the program name from the scalar passed in and to 
##           write the BEGIN line for the program calling beginlog() to the
##           .ulog file.
##           
## HISTORY:
## DATE     DEVELOPER	COMMENTS
## -------- ----------- -----------------------------------------------
## 02/10/06 TMercer	Added header.
##			Added recording of the process id with "PID="
###############################################################################
sub beginlog {

   umask(0);

   $progname = shift(@_); # Need to keep this variable global to this module.

   open( LOG, ">>$LOG_ULOG") or die "Can not write to $LOG_ULOG\n";

   if ( ! defined $_[0] ) {

      print( LOG &gettime."BEGIN: $mypid $progname\n" );
   }
   else {

      print( LOG &gettime."BEGIN: $mypid $progname, @_\n");
   }

   close(LOG) or die "Can not close $LOG_ULOG\n";

   @pathlist = split( /\//, $progname );

   $progname = pop @pathlist;
}


###############################################################################
## FUNCTION: exitlog( )
## AUTHOR:   TMercer
## RECEIVES: 
## RETURNS:  Nothing.
## PURPOSE:  To write the EXIT line for  the calling program to .ulog.
##           
## HISTORY:
## DATE     DEVELOPER	COMMENTS
## -------- ----------- -----------------------------------------------
## 02/10/06 TMercer	Added header.
##			Added recording of the process id with "PID="
##			Added recording of the run time of the program.
###############################################################################
sub exitlog( $$ ) {

   umask(0);

   my $string = shift;
   my $status = shift;

   if ( $progname eq "" ) {

      print "\nError: beginlog not called before exitlog\n\n";

      exit(2);
   }

   open( LOG, ">>$LOG_ULOG") or die "Can not write to $LOG_ULOG\n";

   print LOG &gettime."EXIT: $mypid $progname, $string, exit status $status\n";

   close( LOG ) or die "Can not close $LOG_ULOG\n";

   exit( $status );
}


###############################################################################
## FUNCTION: datalog()
## AUTHOR:   
## RECEIVES: 
## RETURNS:  
## PURPOSE:  
##           
## HISTORY:
## DATE     DEVELOPER	COMMENTS
## -------- ----------- -----------------------------------------------
## 03/20/06 TMercer	Added function header.
###############################################################################
sub datalog {

   my $string = shift;

   umask( 0 );

   chkprogname( "datalog" );

   open( LOG, ">>$LOG_ULOG" ) or die "Can not write to $LOG_ULOG\n";

   print( LOG &gettime."DATALOG $progname, $string\n" );

   close( LOG ) or die "Can not close $LOG_ULOG\n";
}


###############################################################################
## FUNCTION: errorlog()
## AUTHOR:   
## RECEIVES: 
## RETURNS:  
## PURPOSE:  
##           
## HISTORY:
## DATE     DEVELOPER	COMMENTS
## -------- ----------- -----------------------------------------------
## 03/20/06 TMercer	Added function header.
###############################################################################
sub errorlog {

   my $string = shift;

   umask(0);

   chkprogname( "errorlog" );

   open( LOG, ">>$LOG_ULOG") or die "Can not write to $LOG_ULOG\n";

   print( LOG &gettime."ERROR $progname, $string\n");

   close(LOG) or die "Can not close $LOG_ULOG\n";
}


###############################################################################
## FUNCTION: warnlog()
## AUTHOR:   
## RECEIVES: 
## RETURNS:  
## PURPOSE:  
##           
## HISTORY:
## DATE     DEVELOPER	COMMENTS
## -------- ----------- -----------------------------------------------
## 03/20/06 TMercer	Added function header.
###############################################################################
sub warnlog {

   my $string = shift;

   umask(0);

   chkprogname("warnlog");

   open( LOG, ">>$LOG_ULOG") or die "Can not write to $LOG_ULOG\n";

   print( LOG &gettime."WARNING $progname, $string\n");

   close(LOG) or die "Can not close $LOG_ULOG\n";
}


###############################################################################
## FUNCTION: gettime()
## AUTHOR:   
## RECEIVES: 
## RETURNS:  
## PURPOSE:  
##           
## HISTORY:
## DATE     DEVELOPER	COMMENTS
## -------- ----------- -----------------------------------------------
## 03/20/06 TMercer	Added function header.
###############################################################################
sub gettime {

   my $timedate = (time);

   return "${timedate}, ";
}


###############################################################################
## FUNCTION: chkprogname()
## AUTHOR:   
## RECEIVES: 
## RETURNS:  
## PURPOSE:  
##           
## HISTORY:
## DATE     DEVELOPER	COMMENTS
## -------- ----------- -----------------------------------------------
## 03/20/06 TMercer	Added function header.
###############################################################################
sub chkprogname {

   my $name = shift;

   if ($progname eq "") {

      print "\nError: beginlog not called before $name\n\n";

      exit(2);
   }
}


###############################################################################
## FUNCTION: append_to_ulog()
## AUTHOR:   
## RECEIVES: 
## RETURNS:  
## PURPOSE:  
##           
## HISTORY:
## DATE     DEVELOPER	COMMENTS
## -------- ----------- -----------------------------------------------
## 03/20/06 TMercer	Added function header.
## 10/03/06 TMercer	Changed the open statements to be Perl 5.0 compliant
##			for probe testers.
###############################################################################
sub append_to_ulog {

   my $filename = shift;

   umask(0);

   open INF, "<$filename" or die "Can not read $filename: $!\n";

   open LOG, ">>$LOG_ULOG" or die "Can not write to $LOG_ULOG: $!\n";

   print( LOG &gettime."APPENDING $filename\n");

   while( <INF> ) {

      print LOG;
   }

   print( LOG &gettime."END_OF_APPENDING $filename\n");

   close LOG;

   close INF;
}


###############################################################################
## FUNCTION: line_to_ulog()
## AUTHOR:   TMercer
## RECEIVES: Scalar string
## RETURNS:  Nothing.
## PURPOSE:  To append string to .ulog.
##           
## HISTORY:
## DATE     DEVELOPER	COMMENTS
## -------- ----------- -----------------------------------------------
## 09/14/06 TMercer	Created.
###############################################################################
sub line_to_ulog {

   my $string = shift;

   chomp $string;

   umask( 0 );

   open( LOG, ">>$LOG_ULOG" ) or die "Can not write to $LOG_ULOG\n";

   print( LOG "$string\n" );

   close( LOG ) or die "Can not close $LOG_ULOG\n";
}


###############################################################################
## FUNCTION: 
## AUTHOR:   
## RECEIVES: 
## RETURNS:  
## PURPOSE:  
##           
## HISTORY:
## DATE     DEVELOPER	COMMENTS
## -------- ----------- -----------------------------------------------
## 
###############################################################################


__END__

=head1 NAME

ulog - Usage logging

=head1 SYNOPSIS

	use ulog;

	beginlog( $0, @ARGV );

	datalog( "This is a test of datalogging." );

	warnlog( "This is a warning" );

	errorlog( "This is an error" );

	exitlog( "Exiting program", EXIT_STATUS );

	append_to_ulog( filename );

	line_to_ulog( $scalar );

=head1 DESCRIPTION

The ulog modules provides five functions which are useful for logging
information from a perl scripts to the file /var/tmp/.ulog and the
link to /var/tmp/.ulog /tmp.ulog.

=over 4

=item *

The B<beginlog> function takes two arguments, $0 and @ARGV.  This function
should be called at the beginning of the perl script that it is used in.
It insures the capture of the perl script name and the command line 
arguments for logging and use by other functions.

=item *

The B<datalog> function is for logging of a piece of information with the 
keyword DATALOG in the log file.

=item *

The B<warnlog> function is like the datalog function in that it logs a piece
of information with the keyword WARNING in the log file.

=item *

The B<errorlog> function is like the datalog function in that it logs a piece
of information with the keyword ERROR in the log file.

=item *

The B<exitlog> function will log a message and the exit status to the log file
with the keyword EXIT.

=item *

The B<append_to_ulog> function will append the filename passed in to the log file.
This function uses the keywords APPENDING and END_OF_APPENDING.

=item *

The B<line_to_ulog> function will append the scalar passed in to the log file.

=back

=head1 AUTHOR

ulog was written by Tom Mercer 4/23/99.

=cut
