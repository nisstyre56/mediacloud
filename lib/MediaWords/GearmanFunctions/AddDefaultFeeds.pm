package MediaWords::GearmanFunctions::AddDefaultFeeds;

#
# Periodically check for new media sources that have not had default feeds
# added to them and add the default feeds.  Look for feeds that are most likely
# to be real feeds.  If we find more than one but no more than
# MAX_DEFAULT_FEEDS of those feeds, use the first such one and do not moderate
# the source.  Else, do a more expansive search and mark for moderation.
#
# Start this worker script by running:
#
# ./script/run_with_carton.sh local/bin/gjs_worker.pl lib/MediaWords/GearmanFunctions/AddDefaultFeeds.pm
#
# FIXME some output of the job is still logged to STDOUT and not to the log:
#
#    fetch [1/1] : http://www.delfi.lt/
#    got [1/1]: http://www.delfi.lt/
#    fetch [1/22] : http://www.delfi.lt/index.xml
#    got [1/22]: http://www.delfi.lt/index.xml
#    fetch [2/22] : http://www.delfi.lt/atom.xml
#    got [2/22]: http://www.delfi.lt/atom.xml
#    fetch [3/22] : http://www.delfi.lt/feeds
#    got [3/22]: http://www.delfi.lt/feeds
#    fetch [4/22] : http://www.delfi.lt/feeds/default
#    got [4/22]: http://www.delfi.lt/feeds/default
#    fetch [5/22] : http://www.delfi.lt/feed
#    got [5/22]: http://www.delfi.lt/feed
#    fetch [6/22] : http://www.delfi.lt/feed/default
#
# That's because MediaWords::Util::Web::ParallelGet() starts a child process
# for fetching URLs (instead of a fork()).
#

use strict;
use warnings;

use Moose;
with 'Gearman::JobScheduler::AbstractFunction';

BEGIN
{
    use FindBin;

    # "lib/" relative to "local/bin/gjs_worker.pl":
    use lib "$FindBin::Bin/../../lib";
}

use DBIx::Simple::MediaWords;
use Feed::Scrape::MediaWords;
use MediaWords::DB;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

# Run job
sub run($;$)
{
    my ( $self, $args ) = @_;

    my $db = MediaWords::DB::connect_to_db();

    $db->begin_work;

    my $media = $db->query( "select * from media where feeds_added = false order by media_id" )->hashes;

    for my $medium ( @{ $media } )
    {
        my ( $feed_links, $need_to_moderate, $existing_urls ) =
          Feed::Scrape::get_feed_links_and_need_to_moderate_and_existing_urls( $db, $medium );

        for my $feed_link ( @{ $feed_links } )
        {
            my $feed = {
                name        => $feed_link->{ name },
                url         => $feed_link->{ url },
                media_id    => $medium->{ media_id },
                feed_type   => $feed_link->{ feed_type } || 'syndicated',
                feed_status => $need_to_moderate ? 'inactive' : 'active',
            };

            eval { $db->create( 'feeds', $feed ); };

            if ( $@ )
            {
                my $error = "Error adding feed $feed_link->{ url }: $@\n";
                $medium->{ moderation_notes } .= $error;
                print $error;
                next;
            }
            else
            {
                say STDERR "ADDED $medium->{ name }: $feed->{ name } " .
                  "[$feed->{ feed_type }, $feed->{ feed_status }]" . " - $feed->{ url }\n";
            }
        }

        if ( @{ $existing_urls } )
        {
            my $error = "These urls were found but already exist in the database:\n" .
              join( "\n", map { "\t$_" } @{ $existing_urls } ) . "\n";
            $medium->{ moderation_notes } .= $error;
            print $error;
        }

        my $moderated = $need_to_moderate ? 'f' : 't';

        $db->query(
            "update media set feeds_added = true, moderation_notes = ?, moderated = ? where media_id = ?",
            $medium->{ moderation_notes },
            $moderated, $medium->{ media_id }
        );

    }

    $db->commit;

    $db->disconnect;
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;