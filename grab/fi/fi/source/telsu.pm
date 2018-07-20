# -*- mode: perl; coding: utf-8 -*- ###########################################
#
# tv_grab_fi: source specific grabber code for https://www.telsu.fi
#
###############################################################################
#
# Setup
#
# VERSION: $Id$
#
# INSERT FROM HERE ############################################################
package fi::source::telsu;
use strict;
use warnings;

BEGIN {
  our $ENABLED = 1;
}

# Description
sub description { 'telsu.fi' }

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
