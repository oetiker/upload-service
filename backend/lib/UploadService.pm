package UploadService;
use Mojo::Base 'Mojolicious';
use Mojo::Asset::File;
use Data::Dumper;
use Mojo::Util qw(hmac_sha1_sum b64_encode slurp);
use POSIX qw(strftime);

# enable receiving uploads up to 5GB unless already set
BEGIN {
    $ENV{MOJO_MAX_MESSAGE_SIZE} ||= 5 * 1_073_741_824;
}

sub startup {
    my $self = shift;
    my $me = $self;

    # properly figure your own path when running under fastcgi    
    $self->hook( before_dispatch => sub {
        my $self = shift;
        $self->res->headers->header('Access-Control-Allow-Origin' => '*');
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

            $ENV{MOJO_TMPDIR} = $root;

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
            my $newKey =hmac_sha1_sum(rand,time);
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
            $self->render(template=>'uploadpage');
        }
    });

    # GET /upload (retrieves stored file list)
    $a->get('/upload' => sub {
        my $self = shift;
        my $root = $self->stash('root');
        my $sessionkey = $self->stash('skey');
        my @list;
        for my $link (glob $root.'/.*-*-*_*'){
            next if not -l $link;
            my $dest = readlink $link;
            if (not -f $root.'/'.$dest){
                unlink $link;
                next;
            };
            next if $link !~ m[^${root}/\.${sessionkey}];
            my $file = Mojo::Asset::File->new(path=>$root.'/'.$dest);                        
            next unless $file->is_file;
            push @list, {
                name => $dest,
                size => $file->size,
                $ENV{US_ENABLE_DOWNLOAD} ? ( url => 'download/'.$dest ): (),
                $ENV{US_ENABLE_DELETE} ? (
                    deleteUrl =>  'delete/'.$dest,
                    deleteType => 'DELETE'
                ):(),
            };
        }
        return $self->render( json => { files => \@list } );
    });

    # POST /upload (push one or more files to app)
    $a->post('/upload' => sub {
        my $self    = shift;
        my @uploads = $self->req->upload('files[]');

        my @files;
        my $sessionkey = $self->stash('skey');
        my $root = $self->stash('root');
        for my $upload (@uploads) {
            my $filename = $upload->filename;
            my $outfile = strftime("%Y-%m-%d_%H%M%S-$filename",localtime(time));
            $outfile =~ s{/}{_}g;
            if (symlink $outfile, $root. '/.'. $sessionkey .'-'. $outfile and  not -e $root. '/'.  $outfile ){
                eval { 
                    local $SIG{__DIE__};local $SIG{__WARN__};
                    $upload->move_to( $root. '/'.  $outfile ) ; 
                };
                if ($@){
                    $self->app->log->error($@);
                    my $msg = $@;
                    $msg =~ s{\sat\s\S+\sline\s\d+.+}{};
                    push @files, {
                        name => $filename,
                        error => $msg
                    };
                    unlink $root. '/.'. $sessionkey .'-'. $outfile;
                } 
                else {
                    push @files, {
                        name => $outfile,
                        size => $upload->size,
                        $ENV{US_ENABLE_DOWNLOAD} ? ( url => 'download/'.$outfile ): (),
                        $ENV{US_ENABLE_DELETE} ? (
                            deleteUrl =>  'delete/'.$outfile,
                            deleteType => 'DELETE'
                        ):(),
                    };
                }    
            } 
            else {
                push @files, {
                    name => $filename,
                    error => "$!",
                };
            }
        }
        # return JSON list of uploads
        $self->render( json => { files => \@files } );
    });

    if ($ENV{US_ENABLE_DOWLOAD}){
    # /download/files/foo.txt
    $a->get('/download/#key' => sub {
        my $self = shift;
        if (not $self->param('key') =~ m{([^/]+)}){
            $self->res->code(403);
            $self->render( text => 'bad key');
            return;
        }
        my $key  = $1;
        my $sessionkey = $self->stash('skey');
        my $root = $self->stash('root');
        if (not -l $root .'/.'.$sessionkey.'-'.$key ){
            $self->res->code(403);
            $self->render( text => 'access denied: no link');
            return;
        }
        my $file = Mojo::Asset::File->new(path=>$root . '/'. $key);
        if (not $file->is_file){
            $self->res->code(403);
            $self->render( text => 'access denied: no file');
            return;
        }
        $self->render(
            data   => $file->slurp,
            format => 'application/octet-stream'
        );
    });
    }
    if ($ENV{US_ENABLE_DELETE}){    
    # /delete/files/bar.tar.gz
    $a->delete('/delete/#key' => sub {
        my $self = shift;
        if (not $self->param('key') =~ m{([^/]+)}){
            $self->res->code(403);
            $self->render( text => 'bad key');
            return;
        }
        my $key  = $1;
        my $sessionkey = $self->stash('skey');
        my $root = $self->stash('root');
        if (not -l $root .'/.'.$sessionkey.'-'.$key ){
            $self->res->code(403);
            $self->render( text => 'access denied: no link');
            return;
        }
        my $file = Mojo::Asset::File->new(path=>$root . '/'. $key);
        if (not $file->is_file){
            $self->res->code(403);
            $self->render( text => 'access denied: no file');
            return;
        }
        unlink $file->path;
        unlink $root .'/.'.$sessionkey.'-'.$key;
        $self->render( json => 1 );
    });
    }

}

1;
