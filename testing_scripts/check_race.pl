#!/usr/bin/perl -w
##
## Copyright (c) 2011 The University of Utah
## All rights reserved.
##
## This file is part of `csmith', a random generator of C programs.
##
## Redistribution and use in source and binary forms, with or without
## modification, are permitted provided that the following conditions are met:
##
##   * Redistributions of source code must retain the above copyright notice,
##     this list of conditions and the following disclaimer.
##
##   * Redistributions in binary form must reproduce the above copyright
##     notice, this list of conditions and the following disclaimer in the
##     documentation and/or other materials provided with the distribution.
##
## THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
## AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
## IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
## ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
## LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
## CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
## SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
## INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
## CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
## ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
## POSSIBILITY OF SUCH DAMAGE.

#################################################################

use strict; 
use File::stat;

#################################################################
#################### user-configurable stuff ####################

# programs shorter than this many bytes are too boring to test
my $MIN_PROGRAM_SIZE = 8000;

# kill Csmith after this many seconds
my $CSMITH_TIMEOUT = 190; 

# kill a compiler after this many seconds
my $COMPILER_TIMEOUT = 230;#extensions need more time

# kill a compiler's output after this many seconds
my $PROG_TIMEOUT = 8;

# extra options here
my $CSMITH_USER_OPTIONS = " ";

#parallel options
my $CSMITH_PARALLEL_OPTIONS = " --parallel-for none --canonical-for";

################# end user-configurable stuff ###################
#################################################################

#################################################################
# TODO
#
# - make it easy to plugin an emulator for testing embedded compilers 
# - automatically fire up a reducer when a bug is found
# - support "reference compilers" that supply checksums but that we're
#   not testing
# - support better configuration of resource limits
#
#################################################################

my $RUN_PROGRAM = 1;#we are always running the programs

my $CSMITH_HOME = $ENV{"CSMITH_HOME"}; 
my $good = 0; 
my $crash_bug = 0;
my $wrongcode_bug = 0;
my $csmith_bug = 0;

my $HEADER = "-I$CSMITH_HOME/runtime";
my $CYGWIN_HEADER = "-I`cygpath -d ${CSMITH_HOME}/runtime`";
my $COMPILE_OPTIONS = "-fopenmp";
my @COMPILERS = "gcc";

sub read_value_from_file($$) {
    my ($fn, $match) = @_;
    open INF, "<$fn" or die;
    while (my $line = <INF>) {
        $line =~ s/\r?\n?$//;            # get rid of LF/CR 
        if ($line =~ /$match/) {
            close INF;
            return $1;
        }     
    }
    close INF;
    return "";
}

sub write_bug_desc_to_file($$) {
    my ($fn, $desc) = @_;
    open OUT, ">>$fn" or die "cannot write to $fn\n";
    print OUT "/* $desc */\n";
    close OUT;
}

# properly parse the return value from system()
sub runit ($$$) {
    my ($cmd, $timeout, $out) = @_; 
    my $res;
    if ($RUN_PROGRAM) {
	$res = system "timeout $timeout $cmd > $out 2>&1";
    } else {
	$res = system "$cmd > $out 2>&1";
    }
    my $success = 0; 
    if ($? == -1) {
        print "can't execute $cmd\n";
    }
    elsif ($? & 127) {
        print "died while executing $cmd\n";
    }
    elsif ($res == -1) {
        print "can't execute $cmd\n";
    }
    else {
        $success = 1;
    }
    my $exit_value  = $? >> 8;
    if ($exit_value == 124) {
        print "hangs while executing $cmd\n";
        $success = 0;
    }
    return ($success, $exit_value);
}

#--------------------------ABOVE THIS IS GENERIC, NO NEED TO TOUCH--------------------------

# compile a program and execute
# return code 	      0: normal; 
#                     1: compiler crashes; 
#                     2: compiler hangs; 
#                     3: executable crashes; 
#                     4: executable hangs
sub compile_and_run($$$$) {
    my ($compiler, $src_file, $exe, $out) = @_; 
    my $command = "$compiler $src_file $COMPILE_OPTIONS $HEADER -o $exe";  

    my @a = split(" ", $compiler);
    # special treatment of MS compiler: convert header path to unix-style
    if ($a[0] =~ /cl$/) {
        $command = "$compiler $src_file $COMPILE_OPTIONS $CYGWIN_HEADER -o $exe"; 
    }  

    # compile random program
    my ($res, $exit_value) = runit($command, $COMPILER_TIMEOUT,  "compiler.out"); 
    # print "after run compiler: $res, $exit_value\n";
    if (($res == 0) || (!(-e $exe))) {
        # exit code 124 means time out
        return ($exit_value == 124 ? 2 : 1);         
    }
	my $chksum;
    # run random program 
    if ($RUN_PROGRAM) {

        ($res, $exit_value) = runit("./$exe", $PROG_TIMEOUT, $out);
	if ($res!=0){
		$chksum = read_value_from_file($out, "checksum = (.*)");	
	}
        # print "after run program: $res, $exit_value\n";
        if (($res == 0) || (!(-e $out))) {
            # exit code 124 means time out
            return ( ($exit_value == 124 ? 4 : 3), $chksum);      
        }
    }
    return (0, $chksum);
}

# evaluate a random program
# return code:  -2: crashes (a likely wrong-code bug)
#                        -1: hangs (not interesting)
#                        0: normal, but found no compiler error (not interesting)
#                        1: found compiler crash error(s)
#                        2: found compiler wrong code error(s) 
sub evaluate_program ($) {
    my ($test_file) = @_; 
    my @checksums;
    my @tested_compilers; 
    my $interesting = 0;
    my $i = 0;     
    my $chksum_glob=-1;
    foreach my $compiler (@COMPILERS) { 
        my $out = "out$i.log";
        my $exe = "a.out$i";
        $i++; 
        my ($res,$chksum_local) = compile_and_run($compiler, $test_file, $exe, $out);
	$chksum_glob = $chksum_local;
        if ($res) {
	    if ($res == 1 || $res == 2) { 
		write_bug_desc_to_file($test_file, 
		  "Compiler error! Can't compile with $compiler $COMPILE_OPTIONS $HEADER"); 
		$interesting = 1;
            }
            elsif ($res == 3) { 
		write_bug_desc_to_file($test_file, "random program crashed!"); 
		# random program crashes, a likely wrong-code bug, but
		# can't rule out the probablity of a Csmith bug
		$interesting = -2;     
                last;
	    } else {
		print "random program hangs!\n";  
                # program hangs, not interesting
		$interesting = -1;    
                last;
            }
        }
        else {
            if ($RUN_PROGRAM) {
                die "cannot find $out.\n" if (!(-e $out));
                my $sum = read_value_from_file($out, "checksum = (.*)");
                $interesting = 2 if 
		    (scalar(@checksums) > 0 && $sum ne $checksums[0]); 
                push @checksums, $sum;
                push @tested_compilers, "$compiler $COMPILE_OPTIONS";
            }             
        }
    } 
    if ($interesting >= 1) {
        if ($interesting == 2) { 
            write_bug_desc_to_file ($test_file, 
				    "Found checksum difference between compiler implementations"); 
            for (my $i=0; $i < scalar (@checksums); $i++) {
                write_bug_desc_to_file ($test_file, 
		  "$tested_compilers[$i]: $checksums[$i]");
            }
        }
        write_bug_desc_to_file($test_file, 
	  "please refer to http://embed.cs.utah.edu/csmith/using.html on how to report a bug");
    }
    system "rm -f out*.log a.out* test*.obj compiler.out csmith.out";
    return ($interesting,$chksum_glob);
}

sub eval_sequ($){
    (my $cfile) = @_;
    # test if the random program is interesting
    my ($ret,$chksum) = evaluate_program($cfile); 
    if ($ret >= 0) {
        $good++;
        print "GOOD PROGRAM: number $good\n";
	print "checksum is : $chksum";
        if ($ret == 1) {
            print "COMPILER CRASH ERROR FOUND: number $crash_bug\n";
            $crash_bug++;
            system "cp $cfile crash${crash_bug}.c";
        }
        if ($ret == 2 || $ret == -2) {
            print "LIKELY WRONG CODE ERROR FOUND: number $wrongcode_bug\n";
            $wrongcode_bug++;
            system "cp $cfile wrong${wrongcode_bug}.c";
        } 
    } else { 
        print "BAD PROGRAM: doesn't count towards goal.\n";
    }  

    unlink $cfile;
    return ($ret, $chksum);
}
sub test_one ($) {
    (my $n) = @_;	#@_ has the current value, passed as parameter (i in this case)
    my $cfile = "seq_test$n.c";
    my $seed;
    my $filesize;

    # run Csmith until generate a big enough program
    while (1) {
        unlink $cfile;
        my $cmd = "$CSMITH_HOME/src/csmith $CSMITH_USER_OPTIONS --output $cfile";
        my ($res, $exitcode) = runit($cmd, $CSMITH_TIMEOUT,  "csmith.out"); 
        #print "after run csmith: $res, $exitcode\n";
	
        $seed = read_value_from_file($cfile, "Seed:\\s+([0-9]+)");
        die "Random program $cfile has no seed information!\n" if (!$seed);  

        if ($res == 0) {
	    print "CSMITH BUG FOUND: number $csmith_bug\n";
	    $csmith_bug++;
	    system "cp $cfile csmith_bug_${csmith_bug}.c"; 
	    next; #continue similar
        }
        else { 
            $filesize = stat("$cfile")->size;
            last if ($filesize >= $MIN_PROGRAM_SIZE);	#last means break
        }
    }
#----
	my $cfile_parallel= "parallel_test$n.c";
        my $cmd = "$CSMITH_HOME/src/csmith -s $seed $CSMITH_PARALLEL_OPTIONS --output $cfile_parallel";
        my ($res, $exitcode) = runit($cmd, $CSMITH_TIMEOUT,  "csmith.out"); 
        #print "after run csmith: $res, $exitcode\n";
	
        $seed = read_value_from_file($cfile, "Seed:\\s+([0-9]+)");
        die "Random parallel program $cfile_parallel has no seed information!\n" if (!$seed);  

        if ($res == 0) {
	    print "CSMITH BUG FOUND: number $csmith_bug\n";
	    $csmith_bug++;
	    system "cp $cfile_parallel csmith_bug_${csmith_bug}.c"; 
	    next; #continue similar
        }
#----
    	print "\nseed= $seed, size= $filesize\n";
	my ($ret,$chksum_sequential) = eval_sequ($cfile);
	print "\nsame seed with parallel options enabled\n";
	my ($ret,$chksum_parallel) = eval_sequ($cfile_parallel);#this compiles and runs parallel
	if ($chksum_sequential eq $chksum_parallel){
		print "\nBOTH CHECKSUMS MATCH\n";
	}
	else{
		print "\nchecksum don't match\n";
		exit(-1);
	}
	return $ret;
}
sub usage () {
	print "give the count ./check_race [count]\n";
    exit -1;
}

########################### main ##################################


my $cnt = $ARGV[0];
usage() unless ($cnt =~ /^[0-9]+$/ && $cnt >= 0);

# MAIN LOOP
my $i = 0;
while ($cnt == 0 || $i < $cnt) {
    if (test_one ($i) != -1) {
	$i++;
    }
    print "\n";
} 



##################################################################
