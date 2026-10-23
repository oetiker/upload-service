use strict;
use warnings;
use utf8;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../thirdparty/lib/perl5";
use File::Temp qw(tempdir);
use Mojo::File qw(path);
use Mojo::Log;
use Mojo::Util qw(encode);
use Test::More;
use Test::Mojo;

my $root = tempdir(CLEANUP => 1);
$ENV{US_ROOT}       = $root;
$ENV{US_SINGLEUSER} = 1;
$ENV{US_TAGMODE}    = 1;
$ENV{MOJO_LOG_LEVEL} = 'info';

my $t = Test::Mojo->new('UploadService');
my @log;
$t->app->log(Mojo::Log->new(level => 'info'));
$t->app->log->unsubscribe('message')->on(message => sub {
    my ($log, $level, @lines) = @_;
    push @log, "[$level] @lines";
});

sub upload {
    my ($name, $content, %extra) = @_;
    return $t->post_ok('/testtag/upload' => form => {
        resumableIdentifier       => length($content).'-x',
        resumableFilename         => $name,
        resumableChunkNumber      => 1,
        resumableChunkSize        => 1048576,
        resumableTotalChunks      => 1,
        resumableCurrentChunkSize => length($content),
        file => { content => $content, filename => 'blob' },
        %extra,
    });
}

sub stored {
    opendir my $dh, $root or die $!;
    my @f = grep { !/^\./ && -f "$root/$_" } readdir $dh;
    return @f;
}

$t->get_ok('/')->status_is(200);
$t->get_ok('/testtag/')->status_is(200)->content_like(qr/Resumable/);

subtest 'plain file name is stored with tag prefix' => sub {
    @log = ();
    upload('report.pdf', 'hello')->status_is(200)->content_is('ok');
    my ($f) = grep { /report\.pdf$/ } stored();
    like $f, qr/^testtag-\d{4}-\d\d-\d\d_\d\d-\d\d-\d\d_report\.pdf$/, 'name';
    is path("$root/$f")->slurp, 'hello', 'content';
    ok( (grep { /upload complete .*testtag.*report\.pdf, 5 bytes, 1 chunks/ } @log), 'success logged');
};

subtest 'umlauts and brackets are kept or replaced, not rejected' => sub {
    @log = ();
    upload('Übersicht (1) & Co.pdf', 'x')->status_is(200);
    my $want = encode('UTF-8', '_Übersicht (1) _ Co.pdf');
    ok( (grep { substr($_, -length $want) eq $want } stored()), 'cleaned name') or diag join "\n", stored();
};

subtest 'decomposed umlaut from macOS is normalised' => sub {
    upload("Mu\x{0308}ller.txt", 'x')->status_is(200);
    my $want = encode('UTF-8', "_M\x{fc}ller.txt");
    ok( (grep { substr($_, -length $want) eq $want } stored()), 'NFC name') or diag join "\n", stored();
};

subtest 'path components are dropped' => sub {
    upload('../../etc/passwd', 'x')->status_is(200);
    ok( (grep { /_passwd$/ } stored()), 'stored as passwd inside INBOX');
    ok !-e "$root/../etc", 'nothing outside';
    upload('C:\\temp\\win.txt', 'x')->status_is(200);
    ok( (grep { /_win\.txt$/ } stored()), 'windows path dropped');
};

subtest 'unusable names are rejected and logged' => sub {
    @log = ();
    upload('...', 'x')->status_is(400)->content_is('invalid filename');
    ok( (grep { /^\[warn\] rejected POST \/testtag\/upload from .* \(.*tag testtag\): invalid filename \[\.\.\.\]/ } @log),
        'rejection logged') or diag join "\n", @log;
};

subtest 'invalid identifier is rejected and logged' => sub {
    @log = ();
    $t->post_ok('/testtag/upload' => form => {
        resumableIdentifier => '../x', resumableFilename => 'a.txt',
        file => { content => 'x', filename => 'blob' },
    })->status_is(400)->content_is('invalid file identifier');
    ok( (grep { /invalid file identifier \[\.\.\/x\]/ } @log), 'logged');
};

subtest 'size mismatch is logged' => sub {
    @log = ();
    upload('size.txt', 'abc', resumableCurrentChunkSize => 5)->status_is(206);
    ok( (grep { /upload size was not as expected \[size\.txt chunk 1\/1: got 3 bytes, expected 5\]/ } @log), 'logged');
};

subtest 'invalid tag is rejected and logged' => sub {
    @log = ();
    $t->get_ok('/Bad-Tag/')->status_is(403);
    ok( (grep { /tags must consist of 0-9 and a-z \[Bad-Tag\]/ } @log), 'logged');
};

subtest 'control characters are escaped in the log' => sub {
    @log = ();
    upload('a.txt', 'x', resumableIdentifier => "1-a\nfake log line")->status_is(400);
    ok( (grep { /\[1-a\\x0afake log line\]/ } @log), 'newline escaped') or diag join "\n", @log;
};

subtest 'email mode rejects a bad address before storing anything' => sub {
    local $ENV{US_EMAILMODE} = 1;
    my @before = stored();
    upload('mail.txt', 'x', email => '../evil')->status_is(400)->content_is('invalid email');
    is scalar(stored()), scalar(@before), 'nothing stored';
    upload('mail.txt', 'x', email => 'a@example.com')->status_is(200);
    ok( (grep { /_mail\.txt$/ } path("$root/a\@example.com")->list->map('basename')->each), 'stored in email dir');
};

subtest 'page language follows Accept-Language' => sub {
    $t->get_ok('/testtag/' => {'Accept-Language' => 'de-CH,de;q=0.9,en;q=0.8'})
      ->status_is(200)
      ->element_exists('html[lang="de"]')
      ->text_is('title' => 'Datei-Upload')
      ->text_is('h1.text-center' => 'Dateien hochladen')
      ->content_like(qr/Dateien auswählen/)
      ->content_unlike(qr/INBOX/);
    $t->get_ok('/testtag/' => {'Accept-Language' => 'fr-CH, en;q=0.5'})
      ->element_exists('html[lang="fr"]')
      ->text_is('h1.text-center' => 'Envoyer des fichiers');
    $t->get_ok('/testtag/' => {'Accept-Language' => 'it;q=1, de;q=0.3'})
      ->element_exists('html[lang="de"]', 'first supported language by quality');
    $t->get_ok('/testtag/' => {'Accept-Language' => 'ja'})
      ->element_exists('html[lang="en"]')
      ->text_is('h1.text-center' => 'Upload files');
    $t->get_ok('/testtag/')->element_exists('html[lang="en"]', 'no header');
};

subtest 'running version is shown' => sub {
    $t->get_ok('/testtag/')
      ->text_is('.us-version' => "upload-service $UploadService::VERSION");
};

done_testing;
