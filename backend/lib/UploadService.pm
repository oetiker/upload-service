package UploadService;
use Mojo::Base 'Mojolicious';
use Mojo::Asset::File;
use Data::Dumper;
use Mojo::Util qw(hmac_sha1_sum b64_encode slurp);
use POSIX qw(strftime);
use Fcntl 'SEEK_SET';
use autodie;

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

    # session is valid for 1 day
    $self->secret(slurp($ENV{US_SECRET_FILE})) if $ENV{US_SECRET_FILE} and -r $ENV{US_SECRET_FILE};
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
                $self->res->code(403);
                $self->render( text => 'no INBOX directory');
                return;
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
               $self->res->code(403);
               $self->render( text => 'invalid user');
               return;
            }
            my $username = $1;
            $self->stash('user'=>$username);
            my $root_dir = $ENV{US_ROOT} || '/tmp';
            my $root = $root_dir . '/'. $username . '/INBOX';

            $self->stash(root=>$root);
    
            my $uid = getpwnam($username);
            if (not $uid){
                $self->res->code(403);
                $self->render( text => 'unknown user');
                return;
            }
            # lets see if  we can do a bit of user switching
            if ($< == 0 and $> != $uid ){
                # switch uid
                $> = 0;
                $> = $uid;
                if ($> != $uid){
                    $self->res->code(403);
                    $self->render( text => 'access denied: '.$!);
                    return;
                }
            }
            
            if ( -l $root or not -w $root or not -d $root ) {
                $self->res->code(403);
                $self->render( text => 'no INBOX directory in sandbox');
                return;
            }
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
            $self->res->code(403);
            $self->render( text => 'invalid session key');
            return;
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
            $self->render(template=>'resumable');
        }
    });

    # GET /upload (retrieves stored file list)
    $a->get('/upload' => sub {
        my $self = shift;
        my $root = $self->stash('root');
        my $sessionkey = $self->stash('skey');
        my $name = '.'.$sessionkey.'-'.cleanName($self->param('resumableIdentifier'));  
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
        my $sessionkey = $self->stash('skey');
        my $root = $self->stash('root');
        my $name = '.'.$sessionkey.'-'.cleanName($self->param('resumableIdentifier'));  
        my $chunkNr = int($self->param('resumableChunkNumber'));
        my $chunkSize = int($self->param('resumableChunkSize'));
        my $chunkTotal = int($self->param('resumableTotalChunks'));
        my $thisChunkSize = int($self->param('resumableCurrentChunkSize'));
        my $data = $self->req->upload('file')->slurp;
        my $dataLen = length($data);
        if ($dataLen != $thisChunkSize){
            $self->render(status=>206,text=>'upload size was not as expected');
            return;
        }
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
        rename $file,$root.'/'.strftime('%Y-%m-%d_%H-%M-%S_',localtime(time)).$self->param('resumableFilename');
        unlink @rm;
    });
}

sub cleanName {
    my $name = shift;
    $name =~ s/[^-_a-z0-9]+/_/g;
    return $name;
}

1;
