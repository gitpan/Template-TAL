=head1 NAME

Template::TAL - Process TAL templates with Perl

=head1 SYNOPSIS

  # create the TT object, telling it where the templates are
  my $tt = Template::TAL->new( include_path => "./templates" );

  # data to interpolate into the template
  my $data = {
    foo => "bar",
  };

  # process the template from disk (in ./templates/test.tal) with the data
  print $tt->process("test.tal", $data);

=head1 DESCRIPTION

L<TAL|http://www.zope.org/Wikis/DevSite/Projects/ZPT/TAL> is a templating
language used in the Zope CMS. Template::TAL is a Perl implementation of
TAL based on the published specs on the Zope wiki.

TAL templates are XML documents, and use attributes in the TAL namespace to
define how elements of the template should be treated/displayed.  For example:

  my $template = <<'ENDOFXML';
  <html xmlns:tal="http://xml.zope.org/namespaces/tal">
    <head>
      <title tal:content="title"/>
    </head>
    <body>
      <h1>This is the <span tal:replace="title"/> page</h1>
      <ul>
        <li tal:repeat="user users">
          <a href="?" tal:attributes="href user/url"><span tal:replace="user/name"/></a>
        </li>
      </ul>
    </body>
  </html>  
  ENDOFXML

This template can be processed by passing it and the parameters to the
C<process> method:

  my $tt = Template::TAL->new();
  $tt->process(\$template, {
    title => "Bert and Ernie Fansite",
    users => [
      { url => "http://www.henson.com/",         name  => "Henson",       },
      { url => "http://www.sesameworkshop.org/", name  => "Workshop",     },
      { url => "http://www.bertisevil.tv/",      name  => "Bert is Evil", },
    ],
  })

Alternativly you can store the templates on disk, and pass the filename to
C<process> directly instead of via a reference (as shown in the synopsis above.)

Template::TAL is designed to be extensible, allowing you to load templates from
different places and produce more than one type of output.  By default the XML
template will be output as cross-browser compatible HTML (meaning, for example,
that image tags won't be closed.)  Other output formats, including well-formed
XML, can easily be produced by changing the output class (detailed below.)

For more infomation on the TAL spec itself, see 
http://www.zope.org/Wikis/DevSite/Projects/ZPT/TAL%20Specification%201.4

=cut

package Template::TAL;
use warnings;
use strict;
use Carp qw( croak );

use Scalar::Util qw( blessed );

our $VERSION = "0.8";

use Template::TAL::Template;
use Template::TAL::Provider;
use Template::TAL::Provider::Disk;
use Template::TAL::Output::XML;
use Template::TAL::Output::HTML;

=head1 METHODS

=over

=item new( include_path => ['/foo/bar'], charset => 'utf-8' )

Creates and initializes a new Template::TAL object. Options valid here are:

=over

=item include_path

If this parameter is set then it is passed to the provider, telling it where
to load files from disk (if applicable for the provider.)

=item charset

If this parameter is set then it is passed to the output, telling it what
charset to use instead of its default.  The default output class will use the
'utf-8' charset unless you tell it otherwise.

=item provider

Pass a 'provider' option to specify a provider rather than using the default
provider that reads from disk.  This can either be a class name of a loaded
class, or an object instance.

=item output

Pass a 'output' option to specify a output class rather than using the default
output class that dumps the DOM tree to as a string to create HTML.  This can
either be a class name of a loaded class, or an object instance.

=back

=cut

sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;

  # if we've got a provider, set it
  if (exists $args{provider}) {
    $self->provider( delete $args{provider} );
  }

  # if we've got an include path, pass it to the provider
  if (exists $args{include_path}) {
    $self->provider->include_path(delete $args{include_path});
  }

  # if we've got an output set it
  if (exists $args{output}) {
    $self->output( delete $args{output} );
  }

  # if we've got a charset, pass it to the output
  if (exists $args{charset}) {
    $self->output->charset( delete $args{charset} );
  }

  return $self;
}

sub provider {
  my $self = shift;
  return $self->{provider} ||= Template::TAL::Provider::Disk->new() unless @_;
  $self->{provider} = blessed($_[0]) ? $_[0] : $_[0]->new();
  return $self;
}

sub output {
  my $self = shift;
  return $self->{output} ||= Template::TAL::Output::HTML->new() unless @_;
  $self->{output} = blessed($_[0]) ? $_[0] : $_[0]->new();
  return $self;
}

=item process( $template, $data_hashref )

Process the template with the passed data and return the resulting rendered
byte sequence.

C<$template> can either be a string containing where the provider should get
the template from (i.e. the filename of the template in the include path), a
reference to a string containing the literal text of the template, or a
Template::TAL::Template object.

C<$data_hashref> should be a reference to a hash containing the values that
are to be substituted into the template.

=cut

sub process {
  my ($self, $template, $data) = @_;

  if (!ref $template) {
    $template = $self->provider->get_template( $template )
  } elsif (ref($template) eq 'SCALAR') {
    # scalar reference - a reference to source of a template
    $template = Template::TAL::Template->new->source($$template);
  } elsif (!UNIVERSAL::isa($template, 'Template::TAL::Template')) {
    croak("Can't understand object of type ".ref($template)." as a template");
  }

  # TODO - Add METAL language module here, while we have the provider.
#   $template->add_language(
#     Template::TAL::Language::METAL->new->provider( $self->provider )
#   );

  my $dom = $template->process($data);
  return $self->output->render( $dom );
}

=back

=head1 ATTRIBUTES

These are get/set chained accessor methods that can be used to alter the object
after initilisation (meaning they return their value when called without
arguments, and set the value and return $self when called with.)

In both cases you can set these to either class names or actual instances
and they with do the right thing.

=over

=item provider

The instance of the L<Template::TAL::Provider> subclass that will be providing
templates to this engine.

=item output

The instance of the L<Template::TAL::Output> subclass that will be used to
render the produced template output.

=back

=head1 RATIONALE

L<Petal> is another Perl module that can process a templating language
suspiciously similar to TAL.  So why did we implement Yet Another
Templating Engine?  Well, we liked Petal a lot. However, at the time of
writing our concerns with Petal were:

=over

=item

Petal isn't strictly TAL. We consider this a flaw.

=item

Petal assumes rather strongly that templates are stored on disk.  We wanted
a system with a pluggable template source so that we could store templates
in other places (such as a database.)

=item

Petal does lots of caching.  This is a good thing if you've got a small
number of templates compared to the number of pages you serve. However, if 
you've got a vast number of templates - more than you can hold in memory -
then this quickly becomes self defeating.  We wanted code that doesn't have 
any caching in it at all.

=back

In conclusion:  You may be better off using Petal.  Certainly the caching
layer could be very useful to you.

There's more than one way to do it.

=head1 COPYRIGHT

Written by Tom Insam, Copyright 2005 Fotango Ltd. All Rights Reserved.

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 BUGS

Template::TAL creates superfluous XML namespace attributes in the
output.

Please report any bugs you find via the CPAN RT system.
http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Template::TAL

=head1 SEE ALSO

The TAL specification: http://www.zope.org/Wikis/DevSite/Projects/ZPT/TAL%20Specification%201.4

L<Petal>, another Perl implementation of TAL on CPAN.

=cut

1;
