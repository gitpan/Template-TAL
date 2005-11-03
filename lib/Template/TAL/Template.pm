=head1 NAME

Template::TAL::Template - a TAL template

=head1 SYNOPSIS

  my $template = Template::TAL::Template->new->source( "<html>...</html>" );
  my $dom = $template->process( {} );
  print $dom->toString();

=head1 DESCRIPTION

This class represents a single TAL template, and stores its XML source.
You'll probably not see these objects directly - Template::TAL takes template
names and returns bytes. But you might.

=cut

package Template::TAL::Template;
use warnings;
use strict;
use Carp qw( croak );
use XML::LibXML;

use Template::TAL::TALES;
use Template::TAL::Language::TAL;

=head1 METHODS

=over

=item new()

Create a new TAL template object.

=cut

sub new {
  my $class = shift;
  my $self = bless {}, $class;
  # default language is just TAL. We can't add METAL here, because it
  # requires a provider - it should be added by Template::TAL.
  $self->add_language("Template::TAL::Language::TAL");
  return $self;
}

=item source( [ set source ] )

the TAL source of this template, as a scalar

=cut

sub source {
  my $self = shift;
  return $self->{source} unless @_;
  $self->{source} = shift;
  return $self;
}

=item languages

a listref of language plugins this template will use when parsing. All
templates get at least the L<Template::TAL::Language:TAL> language module.

=cut

sub languages {
  my $self = shift;
  return $self->{languages} ||= [] unless @_;
  $self->{languages} = ref($_[0]) ? shift : [ @_ ];
  return $self;
}

=item add_language( language module, module, module... )

adds a language to the list of those used by the template renderer. 'module'
here can be a classname or an instance.

=cut

sub add_language {
  my $self = shift;
  push( @{ $self->{languages} }, ( map { ref($_) ? $_ : $_->new } @_ ) );
  return $self;
}

=item process( data hash )

processes the template object, returns an XML::LibXML::Document object.
The data hash passed in forms the global context of the tempalte. The
template code will be able to change this hash using the tal:define
directive in 'global' mode (see L<Template::TAL::Language::TAL>).

=cut

sub process {
  my ($self, $data) = @_;

  # parse the template as XML
  my $parser = XML::LibXML->new();
  my $document = $parser->parse_string($self->source);

  # walk the template, converting the DOM tree as we go. Local context
  # starts as empty, global context is the template data.
  $self->process_node( $document->documentElement, {}, $data );

  return $document;
}

=item process_node( node, local context, global context)

this processes a given DOM node with the passed contexts, using the
Template instance's language plugins, and manipulates the DOM node
according to the instructions of the plugins. Returns nothing
interesting - it is expected to change the DOM tree in place.

=cut

sub process_node {
  my ($self, $node, $local_context, $global_context) = @_;

  # a mapping of namespaces->plugin class for fast lookup later.
  my %namespaces = map { $_->namespace => $_ } @{ $self->languages };
  
  # we have to make a distinction between local and global context,
  # because the define tag can set into the global context. Curses.
  $global_context ||= {};
  $local_context ||= {};

  # make a shallow copy. Shallow is enough, because we can't set deep paths.
  $local_context = { %$local_context };

  # we only care about handling elements - text nodes, etc, don't have
  # attributes and therefore can't be munged.
  return unless $node->nodeType == 1;

  # record attributes of the node we're processing, but leave them
  # in place, so recursive processing gets a chance to look at them
  # agian later
  my %attrs; # will be $attrs{ language module }{ tag name }
  for ($node->attributes) {
    my $uri = $_->getNamespaceURI;
    next unless $uri and $_->nodeType == 2; # attributes with namespaces only
    if ( $namespaces{ $uri } ) {
      # we have a handler for this namespace
      $attrs{ $uri }{ $_->name } = $_->value;
    }
  }

  # have we replaced this node? Track this, so we can stop porcessing earlier.
  my $replaced = 0; 

  # for all our languages (in order)
  LANGUAGE: for my $language ( @{ $self->languages } ) {
    # only process if the language is referenced.
    next unless exists $attrs{ $language->namespace };

    # the languages have an ordered list of tag types they want to deal with.
    OPS: for my $type ($language->tags) {
      next unless exists $attrs{ $language->namespace }{ $type };

      # remove this attribute from the node first, recursive processing
      # wants to see all _other_ attributes, but not the one that caused
      # the recursion in the first place.
      $node->removeAttributeNS( $language->namespace, $type );
      
      # handle this attribute
      my $sub = "process_$type"; $sub =~ s/\-/_/;
      my @replace = $language->$sub($self, $node, $attrs{ $language->namespace }{ $type }, $local_context, $global_context);
  
      # remove from the todo list, so we can track unhandled attributes later.
      delete $attrs{ $language->namespace }{ $type };
  
      # if we're replacing the node with something else as a result of the
      # attribute, do so. Once we've done that, we're finished, so leave.
      if (!@replace) {
        # removing the node
        $node->parentNode->removeChild( $node );
  
        $replaced = 1;
        delete $attrs{ $language->namespace }; # because the handler will have dealt with them
        last LANGUAGE;
  
      } elsif (@replace and $replace[0] != $node) {
        # replacing with something else. There's no nice 'replace this
        # single node with this list of nodes' operator, so we need this
        # fairly nasty cludge.
        my $this = shift @replace;
        $node->replaceNode($this);
        for (@replace) {
          $this->parentNode->insertAfter($_, $this);
          $this = $_;
        }
  
        $replaced = 1;
        delete $attrs{ $language->namespace }; # because the handler will have dealt with them
        last LANGUAGE;
      }
  
    } # ops

    # complain about any other attributes on the node
    warn sprintf("unhandled TAL attributes '%s'in namespace '%s' on element '%s' at line %d\n",
                 join(',', keys %{ $attrs{ $language->namespace } }), $language->namespace, $node->nodeName, $node->line_number)
      if %{ $attrs{ $language->namespace } };

  } # languages
  

  # now recurse into child nodes, unless we replaced the current node, in
  # which case we assume that it's been dealt with.
  unless ($replaced) {
    for my $child ( $node->childNodes() ) {
      $self->process_node( $child, $local_context, $global_context );
    }
  }
}

=back

=head1 COPYRIGHT

Written by Tom Insam, Copyright 2005 Fotango Ltd. All Rights Reserved

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=cut

1;
