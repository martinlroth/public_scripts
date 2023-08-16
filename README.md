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

