#!/bin/sh
SCRIPT=`readlink -f $0`
SCRIPTPATH=`dirname $SCRIPT`
cd $SCRIPTPATH
export NO_MINITEST=true
irb -r test_helper
