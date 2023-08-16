# public_scripts - Martin's scripts released to the public

## board_test.sh - a script to get board info

board_test.sh is a script to print out any information that can be found
about a board. It is intended to be useful both for an initial port of a
mainboard to coreboot, and also to help debug issues on a coreboot
platform.

This script installs or builds a number of different tools, to run its
tests, so it's probably best not to run it on an OS drive that you care
about.

As it does install tools using apt, this program is designed to be run
on a Debian based OS. Maybe at some point, that could be expanded to
other distributions as well.

## show_czn_gpios

This script prints  out a table of the enabled iomux & GPIO settings
on a board with a Cezanne APU. It reads the register values and shows
the meaning of what's enabled.

Unfortunately, on CZN and newer chips, a number of registers, including
the iomux registers may be locked down for security purposes. This means
that the registers cannot be read or written from the X86.

TODO: CZN's drive strengths vary based on whether the GPIO is 1.8 or 3.3
volts. A table of the voltage for each GPIO should be added, and the
drive strength should be updated for 3.3V GPIOs.

## show_pco_gpios

This script prints  out a table of the enabled iomux & GPIO settings
on a board with a Picasso APU. It reads the register values and shows
the meaning of what's enabled.
