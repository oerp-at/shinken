#!/bin/sh
#
# Copyright (C) 2009-2014:
#    Gabes Jean, naparuba@gmail.com
#    Gerhard Lausser, Gerhard.Lausser@consol.de
#    Gregory Starck, g.starck@gmail.com
#    Hartmut Goebel, h.goebel@goebel-consult.de
#
# This file is part of Shinken.
#
# Shinken is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Shinken is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with Shinken.  If not, see <http://www.gnu.org/licenses/>.


DIR="$(cd $(dirname "$0"); pwd)"
echo "Going to dir $DIR"

BIN="$DIR"

export LANG=us_US.UTF-8

"$BIN"/launch_scheduler.sh
"$BIN"/launch_poller.sh
"$BIN"/launch_reactionner.sh
"$BIN"/launch_broker.sh
"$BIN"/launch_receiver.sh
"$BIN"/launch_arbiter.sh
