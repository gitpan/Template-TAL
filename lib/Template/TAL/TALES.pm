=head1 NAME

Template::TAL::TALES - parse TALES strings

=head1 SYNOPSIS

  my $string = "path:/foo/bar/0/baz";
  my $value = Template::TAL::TALES->value( $string );
  
=head1 DESCRIPTION

TALES is the recommended syntax for TAL expressions. It is an
extensible syntax that allows you to define any number of expression
types and use them together. See
http://www.zope.org/Wikis/DevSite/Projects/ZPT/TALES
for the spec.

This module is a Perl TALES processor, as well as providing a useful
L<split> utility.

=cut

package Template::TAL::TALES;
use warnings;
use strict;
use Carp qw( croak );
use Scalar::Util qw( blessed );

=head1 METHODS

=over

=item split( string )

commands in 'string' can be split by ';' characters, with raw semicolons
represented as ';;'. This command splits the string on the semicolons, and
de-escapes the ';;' pairs. For instance:

  foo; bar; baz;; narf

splits to:

  ['foo', 'bar', 'baz; narf']

Not technically part of TALES, I think, but really useful for TAL anyway.

=cut

sub split {
  my ($class, $string) = @_;
  # TODO this is _hokey_. Do it properly.
  $string =~ s/;;/\x{12345}/g;
  my @list = grep {$_} split(/\s*;\s*/, $string);
  s/\x{12345}/;/g for @list;
  return @list;
}

=item process_path( path, context, context, context.. )

follows the path into the passed contexts. Will return the value of the
key if it is found in any of the contexts, searching first to last, or
undef if not. Path is something like

  /foo/bar/0/baz/narf

and this will map to (depending on the object types in the context)

  $context->{foo}->bar()->[0]->{baz}->narf();

=cut

# TODO - it would be very nice to distinguish between 'key not found' and
# 'key value is undef'.

sub process_path {
  my ($class, $path, @contexts) = @_;
  my @components = split(/\s*\|\s*/, $path);

  CONTEXT: for my $context (@contexts) {

    COMPONENT: for my $component (@components) {
      $component =~ s!^/!!;
      my @atoms = split(m!/!, $component);
      my $local = $context;
      for my $atom (@atoms) {
        # TODO - unlike Template Toolkit, we use 'can' here, as opposed to
        # just trying it and looking for errors. Is this the right thing?
        if (ref($local) and blessed($local) and $local->can($atom) ) {
          $local = $local->$atom();
          # TODO what about objects that support hash de-referencing or something?
        } elsif (UNIVERSAL::isa($local, "HASH")) {
          $local = $local->{ $atom };
        } elsif (UNIVERSAL::isa($local, "ARRAY")) {
          no warnings 'numeric';
          if ($atom eq int($atom)) {
            $local = $local->[ $atom ];
          } else {
            #warn "$atom is not an array index\n";
            $local = undef;
          }
        } else {
          # TODO optional death here?
          #warn "Can't walk path '$atom' into object '$local'\n";
          $local = undef;
        }

      } # atom
      return $local if defined($local);

    } # component

  } # context
  return undef; # give up.
}

=item process_string( string, context, context, .. )

interprets 'string' as a string, and returns it. This includes variable
interpolation from the contexts, for instance, the string

  This is my ${weapon}!

Where the context is

  { weapon => "boomstick' }

will be interpolated properly. Both ${this} and $this style of placeholder
will be interpolated.

=cut

# TODO if $foo = '$bar' and $bar = 3, then '${foo}' will be interpolated
# to '3', not '$bar'. Tricky? need more regexp-fu
sub process_string {
  my ($class, $string, @contexts) = @_;
  $string =~ s/\$\{(.*?)\}/$class->value($1, @contexts)/eg;
  $string =~ s/\$(\w*)/$class->value($1, @contexts)/eg;
  return $string;
}

=item process_not( value, context )

Evaluates 'value' as a TALES string in the context, and return the
boolean value that is its opposite. eg

  not:string:0 - true
  not:/foo/bar - the opposite of /foo/bar

=cut

sub process_not {
  my ($class, $string, @contexts) = @_;
  my $value = $class->value($string, @contexts);
  return !$value;
}

=item value( expression, context, context, .. )

parse a TALES expression in the first param, such as

  string:Hello there
  path:/a/b/c

using the passed contexts (in order) to look up path values. Contexts should
be hashes, and we will look in each context for a defined key of the given
path until we find one.

(note - I need the multiple contexts code because TAL lets you set
globals in define statements, so I need a local context, and a global
context)

=cut

sub value {
  my ($class, $exp, @contexts) = @_;
  unless (@contexts) { @contexts = ({}) }
  my ($type, $string) = $exp =~ /^\s*(?:(\w+):\s*)?(.*)/;
  $type ||= "path";
  my $sub = "process_$type";
  if ($class->can($sub)) {
    return $class->$sub($string, @contexts);
  } else {
    die "unknown TALES type '$type'\n";
  }
}

=back

=head1 COPYRIGHT

Written by Tom Insam, Copyright 2005 Fotango Ltd. All Rights Reserved

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=cut

1;
