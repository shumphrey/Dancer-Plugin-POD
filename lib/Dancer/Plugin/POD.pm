=head1 NAME

Dancer::Plugin::POD - A plugin to display all the POD in your local lib.

=head1 SYNOPSYS

In your config.yml

  plugins:
    POD:
      paths: [ '/path/to/lib', '/second/path/to/lib' ]
      prefix: 'pod'
      include_inc: 1
      code_class: 'brush: pl'
      code_tag: 'pre'

=over

=item B<paths> specifies the paths that contain your perl modules.

=item B<prefix> specifies the prefix for all the routes handled by this plugin.

=item B<include_inc> specifies whether to include @INC

=item B<code_class> specifies the class attribute that the <pre> tag will have around pod code blocks.

=item If B<class> is specified, all <pre><code> sections will get replaced with <pre class="B<class>">.
This is designed with L<http://alexgorbatchev.com/SyntaxHighlighter/> in mind but should suit anything.

=item B<code_tag> if specified, defines the tag that code sections will get replaced with. Defaults to 'pre'

=back

In your css :

  /* PERL MODULE LISTING CSS */
  div#pod_listing { }
  #pod_listing > p#pod_listing_header { }
  #pod_listing > p#pod_listing_parent { }
  #pod_listing > ul#pod_listing_ul { }
  #pod_listing_ul { }

  /* POD VIEW CSS */

In your Javascript. 
Download a code highlighter e.g. L<http://alexgorbatchev.com/SyntaxHighlighter/>


In your Dancer App :

  package MyWebService;

  use Dancer;
  use Dancer::Plugin::POD;

=head1 DESCRIPTION

This plugin gives you a POD viewer for Dancer.
The only thing you need to do is set the CSS
and optionally a javascript code hightlighter.

=head1 AUTHORS

This module was written by Steven Humphrey

=cut

package Dancer::Plugin::POD;

use strict;
use warnings;

use Dancer ':syntax';
use Dancer::Plugin;

use Carp;
use DirHandle;
use File::Basename qw();
use File::Spec qw();
use Pod::Simple::Search qw();
use Pod::HTMLEmbed qw();

use Data::Dumper;


my $search_paths = plugin_setting()->{paths} or croak "No config for POD";

my $url_prefix   = plugin_setting()->{prefix} || 'pod';

my $pod_searcher = Pod::HTMLEmbed->new(search_dir   => $search_paths,
                                       url_prefix   => "/$url_prefix/");

## Route Handling
prefix "/$url_prefix" => sub {
    ## Module list within a namespace
    get '/**' => sub {
        my ( $directories ) = splat;

        ## If it ends in .pm or .pl then we are asking for POD
        ## So we'll defer to the next route
        if ( defined $directories && $directories->[-1] =~ m/\.(?:pm|pl|pod)$/ ) {
            pass;
        }

        my $objects = pod_listing($directories);
        return render_pod_listing($objects, pop(@$directories));
    };

    ## View actual POD
    get '/**' => sub {
        my ($module) = splat;
        $module = join('::', @$module);
        $module =~ s/\.(?:pl|pm|pod)$//;

        my $pod = pod($module);
        my $breadcrumbs = generate_breadcrumbs();
        my $toc         = $pod->toc;
        my $body        = $pod->body;

        my $class_attr = plugin_setting()->{'class'};
        if ( defined $class_attr ) {
            $body =~ s/<pre><code>/<pre class="$class_attr">/g;
            $body =~ s#</code></pre>#</pre>#g;
        }

        my $html =<<EOF;
$breadcrumbs
$toc
$body
EOF
        my $template_engine = engine 'template';
        return $template_engine->apply_layout($html);
    };

    ## Root module list
    get '/' => sub {
        my $objects = pod_listing();
        return render_pod_listing($objects);
    };

};

###########################################################
## Helper routines
## You can use these if you want to do your own rendering
###########################################################

## Retrieve a hash reference of alphabetically sorted perl modules
#register pod_listing => sub {
#    my ( $dirs ) = @_;
#    my @dirs = @$dirs if $dirs;
#
#    my @objects = list_files(@dirs);
#
#    my %files;
#    foreach my $obj (@objects) {
#        my ($l) = split //, $obj->{name};
#        $l = uc($l);
#        $files{$l} ||= [];
#        push @{$files{$l}}, $obj;
#    }
#
#    return \%files;
#};

register pod_listing => sub {
    my ( $dirs ) = @_;
    my @dirs = @$dirs if $dirs;

    my $modules = get_modules();

    my $namespace = join('::', @dirs);

    my %objects;
    foreach my $m (keys %$modules) {
        next if $namespace && $m !~ /^${namespace}::/;

        my $file = $modules->{$m};

        my $orig_m = $m;
        $m =~ s/^${namespace}::// if $namespace;
        my $count = $m =~ s/::.*//;

        if ( $count && !defined $objects{$m}->{dir} ) {
            my $name = $m;
            $objects{$m}->{dir} = generate_link(0, $name, @dirs);
        }
        elsif (!defined $objects{$m}->{file} && $orig_m =~ /$m$/ ) {
            my $name = File::Basename::basename($file);
            $objects{$m}->{file} = generate_link(1, $name, @dirs);
        }
    }


    my %names;
    foreach my $obj (sort keys %objects) {
        my ($l) = split //, $obj;
        $l = uc($l);
        $names{$l} ||= [];

        if ( $objects{$obj}->{dir} ) {
            push @{$names{$l}}, $objects{$obj}->{dir};
        }
        if ( $objects{$obj}->{file} ) {
            push @{$names{$l}}, $objects{$obj}->{file};
        }
    }

    return \%names;
};

sub generate_link {
    my ( $is_file, $name, @parts ) = @_;

    my $class = $is_file ? 'pod_listing_file' : 'pod_listing_namespace';

    my $link = sprintf('<a class="pod_listing_link %s" href="/%s">%s</a>',
                       $class,
                       join('/', $url_prefix, @parts, $name),
                       $name);
}

## Retrieve a Pod::HTMLEmbed::Entry object
register pod => sub {
    my ( $module ) = @_;

    #my $pod = $pod_searcher->find($module);
    my $pod = $pod_searcher->load(get_modules()->{$module});

};


## Returns HTML
## TODO: make less ugly.
register render_pod_listing => sub {
    my ($objectlists, $parent) = @_;
    my %objectlists = %$objectlists;

    my $breadcrumbs = generate_breadcrumbs();

    $parent ||= 'Root';

    my $listing = <<EOF;
<div id="pod_listing">
    <h2 id="pod_listing_header">Perl Module List</h2>
    $breadcrumbs
EOF
    foreach my $key (sort keys %objectlists) {
        my $objects = $objectlists{$key};

        $listing .= <<EOF;
	<p class="pod_listing_section">$key</p>
	<ul id="pod_listing_ul">
EOF
        foreach my $obj (@$objects) {
            $listing .= sprintf('<li class="pod_listing_li">%s</li>', $obj);
        }
        $listing .= "\t</ul>\n";
    }
    $listing .= "</div>";

    my $template_engine = engine 'template';
    return $template_engine->apply_layout($listing);
};


## Generate a navigation bar
sub generate_breadcrumbs {
    my (undef, undef, @parts) = split(/\//, request->path);

    my @breadcrumbs = (sprintf('<a class="pod_breadcrumb_link" href="/%s">ROOT</a>', $url_prefix)) if scalar(@parts);
    my $url = '';
    while ( my $part = shift @parts ) {
        $url .= "/$part";
        if ( scalar(@parts) ) {
            push @breadcrumbs, sprintf('<a class="pod_breadcrumb_link" href="/%s%s">%s</a>', $url_prefix, $url, $part);
        } else {
            push @breadcrumbs, $part;
        }
    }

    my $links = join("\n", @breadcrumbs);
    my $html =<<EOF;
<div id='pod_breadcrumbs'>
    $links
</div>
EOF

    return $html;
}


## Find all the directories and files in these paths
#sub list_files {
#    my @dirs = @_;
#
#    my @search_paths = @$search_paths;
#    my %objects;
#    foreach my $search_path (reverse @search_paths) {
#        my $path = path($search_path, @dirs);
#
#        next if !-d $path;
#
#        my $dh = DirHandle->new($path);
#        while(defined(my $child = $dh->read)) {
#            next if ( $child eq '.' || $child eq '..' );
#
#            my $file = path($path, $child);
#            my $urlpath = path(@dirs, $child);
#            my $url  = "/$url_prefix/$urlpath";
#
#            my $object = { name => $child,
#                           url  => $url };
#            if ( -d $file ) {
#                $object->{type} = 'directory';
#                $objects{$child} = $object;
#            }
#            elsif ( $file =~ m/\.(pm|pl)$/ ) {
#                $object->{type} = 'file';
#                $objects{$child} = $object;
#            }
#        }
#    }
#
#    return map { $objects{$_} } sort keys %objects;
#}


## Cache and return the module list
sub get_modules {
    our $module_hash;
    if ( !defined $module_hash ) {
        my $include_lib  = plugin_setting()->{'include_inc'} || 0;
        my $search = Pod::Simple::Search->new->inc($include_lib);
        $module_hash = $search->survey(@$search_paths);
    }
    return $module_hash;
}

register_plugin;

1;

