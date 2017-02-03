#
#  ----------------------------------------------------
#  httpry - HTTP logging and information retrieval tool
#  ----------------------------------------------------
#
#  Copyright (c) 2005-2014 Jason Bittel <jason.bittel@gmail.com>
#

package common_log;

use POSIX qw(strftime mktime);
use Time::Local;

# -----------------------------------------------------------------------------
# GLOBAL VARIABLES
# -----------------------------------------------------------------------------
my %requests = ();
my %requests_time = ();
my $fh;

my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

# -----------------------------------------------------------------------------
# Plugin core
# -----------------------------------------------------------------------------

main::register_plugin();

sub new {
        return bless {};
}

sub init {
        my $self = shift;
        my $cfg_dir = shift;

        _load_config($cfg_dir);

        open OUTFILE, ">$output_file" or die "Cannot open $output_file: $!\n";
        $fh = *OUTFILE;

        return;
}

sub list {
        return qw(direction source-ip dest-ip);
}

sub main {
        my $self = shift;
        my $record = shift;
        my $line = "";
        my $line_suffix;
        my ($milli, $sec, $min, $hour, $mday, $mon, $year);
        my $match_key;
        my $tz_offset;

        if ($record->{'direction'} eq '>') {
                return unless exists $record->{'timestamp'};
                return unless exists $record->{'method'};
                return unless exists $record->{'request-uri'};
                return unless exists $record->{'http-version'};

                # Build the output line: begin with client (remote host) address
                $line .= $record->{'source-ip'};

                # Append ident and authuser fields
                # NOTE: we use the ident field to display the
                # hostname/ip of the destination site
                if (exists $record->{'host'}) {
                        $line .= " $record->{'host'} - ";
                } else {
                        $line .= " $record->{'dest-ip'} - ";
                }

                # Append date field
                $record->{'timestamp'} =~ /(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})(.(\d{1,3}))?/;
                ($milli, $sec, $min, $hour, $mday, $mon, $year) = ($7, $6, $5, $4, $3, $2, $1);
                $time = timelocal($sec,$min,$hour,$mday,$mon,$year)+$milli;
                # NOTE: We assume the current timezone here; that may not always be accurate, but
                # timezone data is not stored in the httpry log files
                $tz_offset = strftime("%z", localtime(mktime($sec, $min, $hour, $mday, $mon, $year)));
                $line .= sprintf("[%04d-%02d-%02d %02d:%02d:%02d%s %5s]", $year, $mon, $mday, $hour, $min, $sec, $milli, $tz_offset);

                # Append request fields
                $line .= " \"$record->{'method'} $record->{'request-uri'} $record->{'http-version'}\"";

                if ($combined_format) {
                        # Append referer
                        if (exists $record->{'referer'}) {
                                $line .= "\t \"$record->{'referer'}\"";
                        } else {
                                $line .= "\t \"-\"";
                        }

                        # Append user agent string
                        if (exists $record->{'user-agent'}) {
                                $line .= " \"$record->{'user-agent'}\"";
                        } else {
                                $line .= " \"-\"";
                        }
                }

                if ($ignore_response) {
                        print $fh "$line - -\n";
                } else {
                        push(@{ $requests{"$record->{'dest-ip'}$record->{'dest-port'}$record->{'source-ip'}$record->{'source-port'}"} }, $line);
                        push(@{ $requests_time{"$record->{'dest-ip'}$record->{'dest-port'}$record->{'source-ip'}$record->{'source-port'}"} }, $time);
                }
        } elsif ($record->{'direction'} eq '<') {
                ##JABEND By adding logic to match on both IP and PORT, the odds of a correct match increases.
                # NOTE: This is a bit naive, but functional. Basically we match a request with the
                # next response from that IP pair in the log file. This means that under busy
                # conditions the response could be matched to the wrong request but currently there
                # isn't a more accurate way to tie them together.
		$match_key = "$record->{'source-ip'}$record->{'source-port'}$record->{'dest-ip'}$record->{'dest-port'}";
                if (exists $requests{"$match_key"}) {
                        $line = shift(@{ $requests{$match_key} });
                        return unless $line;

                        if (! @{ $requests{$match_key} }) {
                                delete $requests{"$record->{'dest-ip'}$record->{'source-ip'}"};
                        }
                } else {
                        return;
                }

                ($line, $line_suffix) = split /\t/, $line, 2 if $combined_format;

                # Append status code
                if (exists $record->{'status-code'}) {
                        $line .= " $record->{'status-code'}";
                } else {
                        $line .= " -";
                }

                # Append byte count
                if (exists $record->{'content-length'}) {
                        $line .= " $record->{'content-length'}";
                } else {
                        $line .= " -";
                }

                # Append transaction time
                $record->{'timestamp'} =~ /(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})(.(\d{1,3}))?/;
                ($milli, $sec, $min, $hour, $mday, $mon, $year) = ($7, $6, $5, $4, $3, $2, $1);
                $time_end = timelocal($sec,$min,$hour,$mday,$mon,$year)+$milli;

		my $time_start = shift(@{ $requests_time{$match_key} });

		$line .=  sprintf "trans_time=%.3fs", ($time_end - $time_start);

                print $fh "$line\n";
        }

        return;
}

sub end {
        # TODO: Print lines that don't have a matching response?

        close $fh or die "Cannot close $fh: $!\n";

        return;
}

# -----------------------------------------------------------------------------
# Load config file and check for required options
# -----------------------------------------------------------------------------
sub _load_config {
        my $cfg_dir = shift;

        # Load config file; by default in same directory as plugin
        if (-e "$cfg_dir/" . __PACKAGE__ . ".cfg") {
                require "$cfg_dir/" . __PACKAGE__ . ".cfg";
        } else {
                die "No config file found\n";
        }

        # Check for required options and combinations
        if (!$output_file) {
                die "No output file provided\n";
        }

        $output_dir = "." if (!$output_dir);
        $output_dir =~ s/\/$//; # Remove trailing slash

        return;
}

1;
