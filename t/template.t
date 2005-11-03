#!perl
use warnings;
use strict;
use Data::Dumper;
use Test::More tests => 5;
use Test::XML;

# extremely simple test - does the Template module take a template, parse
# as xml, and return something?

use Template::TAL::Template;

ok(my $source = <<'END_XML', "got template");
<template>
  text here.
  <br/>
</template>
END_XML

ok(my $expect = <<'END_XML', "got expected output");
<template>
  text here.
  <br/>
</template>
END_XML

ok( my $template = Template::TAL::Template->new->source( $source ), "got template" );

ok( my $dom = $template->process(), "got dom");
is_xml( $dom->toString, $expect, "output is as expected" );
