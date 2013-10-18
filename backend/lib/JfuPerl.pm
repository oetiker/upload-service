package JfuPerl;
use Mojo::Base 'Mojolicious';
use Mojo::Asset::File;
use Data::Dumper;
use Mojo::Util qw(hmac_sha1_sum b64_encode);
use POSIX qw(strftime);
# enable receiving uploads up to 1GB
$ENV{MOJO_MAX_MESSAGE_SIZE} = 1_073_741_824;

has root_dir => '/tmp/sandbox/';

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
    $self->secret('a093l;afslihj;akj;ljasdf.,mdfffdf');
    $self->sessions->cookie_name('uploader');
    $self->sessions->default_expiration(1*24*3600);

    my $r = $self->routes;

    # / (upload page)
    $r->get('/' => 'home');

    my $a = $r->under('/:user' => sub {
        my $self = shift;    
        my $root = $me->root_dir . '/'. $self->param('user') . '/INBOX';
        $self->stash(root=>$root);

        my $uid = getpwnam($self->param('user'));
        if (not $uid){
           $self->res->code(403);
           $self->render( text => 'unknown user');
           return;
        }
        # lets see if  we can do a bit of user switching
        if ($< != $uid ){
            # switch uid
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

        my $sessionkey = $self->session('skey');
        if (not $sessionkey){
            my $newKey =hmac_sha1_sum(rand,time);
            $self->session(skey => $newKey);
        }
        $self->render_later;
    });

    # / (upload page)
    $a->get('/' => sub {
        my $self = shift;
                
        if ($self->req->url !~ m{/$}){
            $self->redirect_to($self->req->url.'/');
        }
        else {
            $self->render(template=>'uploadpage');
        }
    });

    # GET /upload (retrieves stored file list)
    $a->get('/upload' => sub {
        my $self = shift;
        my $sessionkey = $self->session('skey');
        my $root = $self->stash('root');
        my @list;
        for my $link (glob $root.'/.'.$sessionkey.'*'){
            next unless -l $link;
            my $dest = readlink $link;
            my $file = Mojo::Asset::File->new(path=>$root.'/'.$dest);
                        
            next unless $file->is_file;
            push @list, {
                name => $dest,
                size => $file->size,
                url => 'download/'.$dest,
                deleteUrl =>  'delete/'.$dest,
                deleteType => 'DELETE'
            };
        }
        return $self->render( json => { files => \@list } );
    });

    # POST /upload (push one or more files to app)
    $a->post('/upload' => sub {
        my $self    = shift;
        my @uploads = $self->req->upload('files[]');

        my @files;
        my $sessionkey = $self->session('skey');
        my $root = $self->stash('root');
        for my $upload (@uploads) {
            my $filename = $upload->filename;
            my $outfile = strftime("%Y-%m-%d_%H:%M:%S-$filename",localtime(time));
            $outfile =~ s{/}{_}g;
            if (symlink $outfile, $root. '/.'. $sessionkey . $outfile and  not -e $root. '/'.  $outfile ){
                push @files, {
                    name => $outfile,
                    size => $upload->size,
                    deleteUrl => 'delete/'.$outfile,
                    deleteType => 'DELETE',
                    url => 'download/'.$outfile
                };
                $upload->move_to( $root. '/'.  $outfile ) ;
            }
        }
        # return JSON list of uploads
        $self->render( json => { files => \@files } );
    });

    # /download/files/foo.txt
    $a->get('/download/#key' => sub {
        my $self = shift;        
        my $key  = $self->param('key');
        my $sessionkey = $self->session('skey');
        my $root = $self->stash('root');
        if (not -l $root .'/.'.$sessionkey.$key ){
            $self->res->code(403);
            $self->render( text => 'access denied');
            return;
        }
        my $file = Mojo::Asset::File->new(path=>$root . '/'. $key);
        if (not $file->is_file){
            $self->res->code(403);
            $self->render( text => 'access denied');
            return;
        }
        $self->render(
            data   => $file->slurp,
            format => 'application/octet-stream'
        );
    });
    
    # /delete/files/bar.tar.gz
    $a->delete('/delete/#key' => sub {
        my $self = shift;
        my $key  = $self->param('key');
        my $sessionkey = $self->session('skey');
        my $root = $self->stash('root');
        if (not -l $root .'/.'.$sessionkey.$key or -l $root ){
            $self->res->code(403);
            $self->render( text => 'access denied');
            return;
        }
        my $file = Mojo::Asset::File->new(path=>$root . '/'. $key);
        if (not $file->is_file){
            $self->res->code(403);
            $self->render( text => 'access denied');
            return;
        }
        unlink $file->path;
        unlink $root .'/.'.$sessionkey.$key;
        $self->render( json => 1 );
    });

}

1;
