package UploadService;
use Mojo::Base 'Mojolicious';
use utf8;
use Mojo::Asset::File;
use Data::Dumper;
use Mojo::Util qw(hmac_sha1_sum b64_encode encode);
use Mojo::File qw(path);
use POSIX qw(strftime);
use Fcntl 'SEEK_SET';
use Unicode::Normalize qw(NFC);

# make dist writes the release version here; the dist-hook only matches
# double quotes.
our $VERSION = "0.0.0";

# Texts of the upload page. The browser's Accept-Language picks the language,
# English is the fallback.
my %TEXT = (
    en => {
        title         => 'File upload',
        heading       => 'Upload files',
        heading_for   => 'Upload files for %s',
        old_browser   => 'Upload does not work with your browser',
        old_browser_text => 'The upload service needs the HTML5 File API, which every current browser supports. Please update your browser or use a current version of Firefox, Chrome, Edge or Safari.',
        email_label   => 'Email address',
        email_hint    => 'Enter your email address to enable upload',
        select_files  => 'Select files',
        start         => 'Start upload',
        pause         => 'Pause',
        cancel        => 'Cancel',
        waiting       => 'Waiting my turn ...',
        chunking      => 'Preparing file, please wait',
        ready         => 'Ready to upload, press Start!',
        file_done     => 'Upload complete',
        all_done      => 'All uploads complete!',
        progress      => '%1$s MByte/s - %2$s MByte of %3$s MByte',
    },
    de => {
        title         => 'Datei-Upload',
        heading       => 'Dateien hochladen',
        heading_for   => 'Dateien für %s hochladen',
        old_browser   => 'Der Upload funktioniert mit Ihrem Browser nicht',
        old_browser_text => 'Der Upload-Dienst braucht die HTML5 File API, die jeder aktuelle Browser unterstützt. Bitte aktualisieren Sie Ihren Browser oder verwenden Sie eine aktuelle Version von Firefox, Chrome, Edge oder Safari.',
        email_label   => 'E-Mail-Adresse',
        email_hint    => 'E-Mail-Adresse eingeben, um den Upload freizuschalten',
        select_files  => 'Dateien auswählen',
        start         => 'Upload starten',
        pause         => 'Pause',
        cancel        => 'Abbrechen',
        waiting       => 'Wartet ...',
        chunking      => 'Datei wird vorbereitet, bitte warten',
        ready         => 'Bereit, bitte Upload starten!',
        file_done     => 'Upload abgeschlossen',
        all_done      => 'Alle Uploads abgeschlossen!',
        progress      => '%1$s MByte/s - %2$s von %3$s MByte',
    },
    fr => {
        title         => 'Envoi de fichiers',
        heading       => 'Envoyer des fichiers',
        heading_for   => 'Envoyer des fichiers à %s',
        old_browser   => "L'envoi ne fonctionne pas avec votre navigateur",
        old_browser_text => "Le service d'envoi nécessite l'API File HTML5, prise en charge par tous les navigateurs actuels. Veuillez mettre à jour votre navigateur ou utiliser une version actuelle de Firefox, Chrome, Edge ou Safari.",
        email_label   => 'Adresse e-mail',
        email_hint    => "Saisissez votre adresse e-mail pour activer l'envoi",
        select_files  => 'Choisir des fichiers',
        start         => "Démarrer l'envoi",
        pause         => 'Pause',
        cancel        => 'Annuler',
        waiting       => 'En attente ...',
        chunking      => 'Préparation du fichier, veuillez patienter',
        ready         => "Prêt, veuillez démarrer l'envoi !",
        file_done     => 'Envoi terminé',
        all_done      => 'Tous les envois sont terminés !',
        progress      => '%1$s Mo/s - %2$s Mo sur %3$s Mo',
    },
);

# The first language of the Accept-Language header we have texts for.
sub pickLanguage {
    my $header = shift // '';
    my @langs;
    for my $part (split /\s*,\s*/, $header) {
        my ($tag, $q) = $part =~ /^([a-zA-Z]{1,8})(?:-[a-zA-Z0-9]{1,8})*(?:\s*;\s*q\s*=\s*([0-9.]+))?/
            or next;
        push @langs, [lc $tag, $q // 1];
    }
    for my $l (sort { $b->[1] <=> $a->[1] } @langs) {
        return $l->[0] if $TEXT{$l->[0]} and $l->[1] > 0;
    }
    return 'en';
}

sub startup {
    my $self = shift;
    my $me = $self;

    # properly figure your own path when running under fastcgi
    $self->hook( before_dispatch => sub {
        my $self = shift;
        my $reqEnv = $self->req->env;
        my $uri = $reqEnv->{SCRIPT_URI} || $reqEnv->{REQUEST_URI};
        my $path_info = $reqEnv->{PATH_INFO};
        $uri =~ s|/?${path_info}$|/| if $path_info and $uri;
        $self->req->url->base(Mojo::URL->new($uri)) if $uri;
    });

    $self->helper(lang => sub {
        my $c = shift;
        return $c->stash->{'us.lang'} //= pickLanguage($c->req->headers->accept_language);
    });
    $self->helper(l => sub {
        my ($c, $key, @args) = @_;
        my $text = $TEXT{$c->lang}{$key} // $TEXT{en}{$key} // $key;
        return @args ? sprintf($text, @args) : $text;
    });
    # the GECOS full name of the receiving user in multi user mode
    $self->helper(recipient => sub {
        my $c = shift;
        return undef if $ENV{US_SINGLEUSER};
        my $user = $c->stash('user') // return undef;
        my $gecos = (getpwnam($user))[6];
        my ($name) = split /,/, ($gecos // '');
        return (defined $name and length $name) ? $name : $user;
    });

    # session is valid for 1 day
    $self->secrets([path($ENV{US_SECRET_FILE})->slurp]) if $ENV{US_SECRET_FILE} and -r $ENV{US_SECRET_FILE};
    $self->sessions->cookie_name('uploader');
    $self->sessions->default_expiration(1*24*3600);

    my $r = $self->routes;

    my $b;
    # some intial checks
    if ($ENV{US_SINGLEUSER}){
       $b = $r->under(sub {
            my $self = shift;
            $self->stash(user=>scalar getpwuid($>));
            my $root = $ENV{MOJO_TMPDIR} = $ENV{US_ROOT};
            $self->stash(root => $root);
            if ( not -w $root or not -d $root ) {
                return reject($self, 403, 'no INBOX directory', $root);
            }
            $self->render_later;
        })
    }
    else {
        # / (upload page)
        $r->get('/' => 'home');
        $b = $r->under('/:user' => sub {
            my $self = shift;
            if (not $self->param('user') =~ /^(\w+)$/){
               return reject($self, 403, 'invalid user', $self->param('user'));
            }
            my $username = $1;
            $self->stash('user'=>$username);
            my $root_dir = $ENV{US_ROOT} || '/tmp';
            my $root = $root_dir . '/'. $username . '/INBOX';

            $self->stash(root=>$root);

            my $uid = getpwnam($username);
            if (not $uid){
                return reject($self, 403, 'unknown user', $username);
            }
            # lets see if  we can do a bit of user switching
            if ($< == 0 and $> != $uid ){
                # switch uid
                $> = 0;
                $> = $uid;
                if ($> != $uid){
                    return reject($self, 403, 'access denied: '.$!, $username);
                }
            }

            if ( -l $root or not -w $root or not -d $root ) {
                return reject($self, 403, 'no INBOX directory in sandbox', $root);
            }
            $self->render_later;
        });

    }
    if ($ENV{US_TAGMODE}){        # / (upload page)
        if ($ENV{US_SINGLEUSER}){
            $r->get('/' => 'home');
        }
        $b = $b->under('/:tag' => sub {
            my $self = shift;
            if (not $self->param('tag') =~ /^([a-z0-9]+)$/){
               return reject($self, 403, 'tags must consist of 0-9 and a-z', $self->param('tag'));
            }
            my $tag = $1;
            $self->stash('tag'=>$tag);
            $self->render_later;
        });
    }
    $a = $b->under(sub {
        my $self = shift;
        my $sessionkey = $self->session('skey');
        if (not $sessionkey){
            my $newKey = hmac_sha1_sum(rand,time);
            $self->session(skey => $newKey);
        }
        if (not $self->session('skey') =~ /^(\w+)$/){
            return reject($self, 403, 'invalid session key', $self->session('skey'));
        }
        $self->stash(skey => $1);
        $self->render_later;
    });

    # / (upload page)
    $a->get('/' => sub {
        my $self = shift;
        if ($self->req->url ne '' and $self->req->url !~ m{/$}){
            $self->redirect_to($self->req->url.'/');
        }
        else {
            $self->stash(emailMode => $ENV{US_EMAILMODE} ? 1 : 0);
            $self->render(template=>'resumable');
        }
    });

    # GET /upload (retrieves stored file list)
    $a->get('/upload' => sub {
        my $self = shift;
        my $identifier = validateIdentifier($self->param('resumableIdentifier'));
        if (!defined $identifier) {
            return reject($self, 400, 'invalid file identifier', $self->param('resumableIdentifier'));
        }
        my $root = $self->stash('root');
        my $sessionkey = $self->stash('skey');
        my $name = '.'.$sessionkey.'-'.$identifier;
        my $chunkNr = int($self->param('resumableChunkNumber'));
        if (-e $root.'/'.$name.'.'.$chunkNr){
            $self->render(text=>'chunk ok',status=>200);
        }
        else {
            $self->render(text=>'chunk missing',status=>206);
        }
    });

    # POST /upload (push one or more files to app)
    $a->post('/upload' => sub {
        my $self    = shift;
        my $identifier = validateIdentifier($self->param('resumableIdentifier'));
        if (!defined $identifier) {
            return reject($self, 400, 'invalid file identifier', $self->param('resumableIdentifier'));
        }
        my $fileName = cleanFilename($self->param('resumableFilename'));
        if (!defined $fileName) {
            return reject($self, 400, 'invalid filename', $self->param('resumableFilename'));
        }
        my $emailDir = '';
        if ($ENV{US_EMAILMODE}){
            my $email = $self->param('email');
            if (!defined $email || $email =~ /^\./ || $email =~ /\.\./) {
                return reject($self, 400, 'invalid email', $email);
            }
            $emailDir = cleanName($email);
            if (length($emailDir) == 0 || length($emailDir) > 200) {
                return reject($self, 400, 'invalid email', $email);
            }
        }
        my $sessionkey = $self->stash('skey');
        my $root = $self->stash('root');
        my $name = '.'.$sessionkey.'-'.$identifier;
        my $chunkNr = int($self->param('resumableChunkNumber'));
        my $chunkSize = int($self->param('resumableChunkSize'));
        my $chunkTotal = int($self->param('resumableTotalChunks'));
        my $thisChunkSize = int($self->param('resumableCurrentChunkSize'));
        my $upload = $self->req->upload('file');
        if (!$upload) {
            return reject($self, 400, 'no file data in request', $fileName);
        }
        my $data = $upload->slurp;
        my $dataLen = length($data);
        if ($dataLen != $thisChunkSize){
            return reject($self, 206, 'upload size was not as expected',
                "$fileName chunk $chunkNr/$chunkTotal: got $dataLen bytes, expected $thisChunkSize");
        }
        eval {
            use autodie;
            local $SIG{__DIE__};
            my $file = $root.'/'.$name;
            if (not -e $file){
                open my $c,'>>',$file;
                close $c
            }
            open my $fh, "+<", $file;
            binmode $fh,':raw';
            sysseek $fh,($chunkNr-1)*$chunkSize,SEEK_SET;
            syswrite $fh,$data;
            close $fh;
            open my $touch, '>',$file.'.'.$chunkNr;
            close $touch;
            $self->render(text=>'ok',status=>200);
            my @rm;
            for (1..$chunkTotal){
                my $chunk = $root.'/'.$name.'.'.$_;
                return if not -e $chunk;
                push @rm, $chunk;
            }
            my $tag = $self->stash('tag') ? $self->stash('tag').'-' : '';
            if ($emailDir){
                -d $root.'/'.$emailDir || mkdir $root.'/'.$emailDir;
                $emailDir .= '/';
            }
            my $target = $emailDir.$tag.strftime('%Y-%m-%d_%H-%M-%S_',localtime(time)).$fileName;
            my $size = -s $file;
            rename $file,$root.'/'.encode('UTF-8',$target);
            unlink @rm;
            $self->app->log->info(sprintf('upload complete from %s (%s): %s/%s, %d bytes, %d chunks',
                clientAddress($self), requestOwner($self), $root, $target, $size, $chunkTotal));
        };

        if ($@ and $@->isa('autodie::exception')) {
            $self->app->log->error(sprintf('upload failed from %s (%s): %s',
                clientAddress($self), requestOwner($self), "$@"));
            $self->render(status=>404,text=>$@->errno);
        } elsif ($@) {
            die $@;
        }
    });
}

# resumable.js builds the identifier from the file size and the ASCII
# letters, digits, '_' and '-' of the file name; nothing else is expected.
sub validateIdentifier {
    my $name = shift;
    return if !defined $name || length($name) == 0;
    return if length($name) > 200;
    return $name if $name =~ /^[a-zA-Z0-9_-]+$/;
    return;
}

# Browsers send file names with umlauts, brackets, '&' and the like. Rejecting
# them made resumable.js retry the same chunk forever (13154 rejected requests
# for one upload on 2026-10-22/23), so characters outside the safe set are
# replaced instead. Without '/' and '\' the result cannot leave the INBOX.
sub cleanFilename {
    my $name = shift;
    return if !defined $name;
    $name = NFC($name);                 # macOS sends decomposed umlauts
    $name =~ s{.*[/\\]}{};             # keep the last path component only
    $name =~ s/[^\p{L}\p{M}\p{N}_.,()+ -]+/_/g;
    $name =~ s/\.{2,}/./g;
    $name =~ s/^[.\s]+//;               # no hidden files
    $name =~ s/\s+$//;
    if (length($name) > 200) {
        my ($ext) = $name =~ /(\.[^.]{1,16})$/;
        $ext //= '';
        $name = substr($name, 0, 200 - length($ext)) . $ext;
    }
    return if length($name) == 0;
    return $name;
}

sub clientAddress {
    my $c = shift;
    return $c->tx->remote_address // '?';
}

sub requestOwner {
    my $c = shift;
    my @who;
    push @who, 'user '.$c->stash('user') if defined $c->stash('user');
    push @who, 'tag '.$c->stash('tag') if defined $c->stash('tag');
    return @who ? join(', ', @who) : '-';
}

# Log why a request was turned away, then answer it. Returns false so an
# under() callback can end the dispatch with "return reject(...)".
sub reject {
    my ($c, $status, $text, $value) = @_;
    my $detail = defined $value ? $value : '';
    $detail = substr($detail, 0, 300);
    $detail =~ s/([[:cntrl:]])/sprintf('\\x%02x', ord $1)/ge;
    $c->app->log->warn(sprintf('rejected %s %s from %s (%s): %s%s',
        $c->req->method, $c->req->url->path, clientAddress($c), requestOwner($c),
        $text, length $detail ? " [$detail]" : ''));
    $c->render(status => $status, text => $text);
    return;
}

sub cleanName {
    my $name = shift;
    $name =~ s/[^-_a-z0-9@.]+/_/ig;
    return $name;
}

1;
