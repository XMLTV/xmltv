# -*- mode: perl; coding: utf-8 -*- ###########################################
#
# tv_grab_fi: source specific grabber code for https://www.ampparit.com
#
###############################################################################
#
# Setup
#
# VERSION: $Id$
#
# INSERT FROM HERE ############################################################
package fi::source::ampparit;
use strict;
use warnings;

BEGIN {
  our $ENABLED = 1;
}

# Description
sub description { 'ampparit.com' }

# Grab channel list
sub channels {
  return;
}

# Grab one day
sub grab {
  return;
}

# That's all folks
1;
