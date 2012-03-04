=head1 NAME

Dancer::Plugin::POD - A plugin to display all the POD in your local lib.

=head1 SYNOPSIS

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
and optionally a javascript code highlighter.

=head1 AUTHORS

This module was written by Steven Humphrey

=cut

package Dancer::Plugin::POD;

use strict;
use warnings;

use Dancer ':syntax';
use Dancer::Plugin;

use Carp;
use File::Find::Rule::Perl qw();
use Pod::HTMLEmbed qw();


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
        return render_pod_listing($objects);
    };

    ## View actual POD
    get '/**' => sub {
        my ($module) = splat;
        $module = path(@$module);

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

register pod_listing => sub {
    my ( $dirs ) = @_;
    my @dirs = @$dirs if $dirs;

    my $modules = get_modules();

    my $namespace = path(@dirs);

    my %objects;
    foreach my $m (keys %$modules) {
        next if $namespace && $m !~ m#^${namespace}/#;

        my $orig_m = $m;
        $m =~ s#^${namespace}/## if $namespace;
        my $count = $m =~ s#/.*##;

        if ( $count && !defined $objects{"$m/"} ) {
            my $name = "$m/";
            $objects{$name} = {
                path    => path(@dirs, $name),
                name    => $name,
                type    => 0
            };
        }
        elsif (!defined $objects{$m} && $orig_m =~ /$m$/ ) {
            my $name = $m;
            $objects{$name} = {
                path    => path(@dirs, $name),
                name    => $name,
                type    => 1
            };
        }
    }


    ## Group alphabetically by first letter
    my %names;
    foreach my $obj (sort keys %objects) {
        my ($l) = split //, $obj;
        $l = uc($l);
        $names{$l} ||= [];

        push @{$names{$l}}, $objects{$obj};
    }

    return \%names;
};


## Retrieve a Pod::HTMLEmbed::Entry object
register pod => sub {
    my ( $module ) = @_;

    my $pod = $pod_searcher->load(get_modules()->{$module});
};


## Returns HTML
## TODO: make less ugly.
register render_pod_listing => sub {
    my ($objectlists) = @_;
    my %objectlists = %$objectlists;

    my $breadcrumbs = generate_breadcrumbs();

    my $listing = <<EOF;
<div id="pod_listing">
    $breadcrumbs
    <h2 id="pod_listing_header">Perl Module List</h2>
EOF
    foreach my $key (sort keys %objectlists) {
        my $objects = $objectlists{$key};

        $listing .= <<EOF;
	<p name="pod_$key">$key</p>
	<ul class="pod_listing_ul">
EOF

        foreach my $obj (@$objects) {
            my $class = $obj->{type} ? 'pod_dir' : 'pod_file';
            $listing .= sprintf('<li class="%s"><a href="/%s/%s">%s</a></li>', $class,
                                                                           $url_prefix,
                                                                           $obj->{path},
                                                                           $obj->{name});
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

    
    my @breadcrumbs = (sprintf('<li><a href="/%s">main</a></li>', $url_prefix)) if scalar(@parts);
    my $url = '';
    while ( my $part = shift @parts ) {
        $url .= "/$part";
        if ( scalar(@parts) ) {
            push @breadcrumbs, sprintf('<li><a href="/%s%s">%s</a></li>', $url_prefix, $url, $part);
        } else {
            $part =~ s/\.(:?pm|pl|pod)$//;
            push @breadcrumbs, "<li>$part</li>";
        }
    }

    my $links = join("\n", @breadcrumbs);
    my $html =<<EOF;
<ul id='pod_breadcrumbs'>
    $links
</ul>
EOF

    return $html;
}


## Cache and return the module list
sub get_modules {
    our $module_hash;
    if ( !defined $module_hash ) {
        my $include_lib  = plugin_setting()->{'include_inc'} || 0;
        my $arch    = lc( $Config::Config{'archname'} );
        my $ver_qr  = qr#^\d\.\d{1,2}\.\d/#;

        my @search_paths = @$search_paths;
        if ( $include_lib ) {
            push @search_paths, @INC;
        }
        @search_paths = grep { -d $_ } @search_paths;
        
        my $rule = File::Find::Rule->or( File::Find::Rule->perl_module,
                                         File::Find::Rule->perl_script,
                                         File::Find::Rule->name('*.pod') )
                                   ->not_name(qr/^\d/);

        my %files;
        foreach my $dir (@search_paths) {
            $rule->start($dir);
            while ( defined ( my $f = $rule->match ) ) {
                my $orig = $f;

                $f =~ s#^$dir/##;
                $f =~ s#$ver_qr##;
                $f =~ s#^$arch/##;

                $f =~ s#^pod/(.*\.pod)$#$1#;

                ## Prefer pod documents over pm files
                if ( $f =~ /\.pod$/ ) {
                    my $pm = $f;
                    $pm =~ s/\.pod$//;
                    $pm .= '.pm';
                    if ( defined $files{$pm} && $files{$pm} =~ /\.pod$/ ) {
                        $files{$pm} = $orig;
                        delete $files{$f};
                    }
                    elsif ( !defined $files{$pm} ) {
                        $files{$f} = $orig;
                    }
                }
                elsif ( !defined $files{$f} ) {
                    $files{$f} = $orig;
                }
            }
        }

        $module_hash = \%files;
    }
    return $module_hash;
}

register_plugin;

1;

