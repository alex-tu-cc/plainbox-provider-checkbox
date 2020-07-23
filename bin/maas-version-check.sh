#!/bin/bash

# Copyright (C) 2012-2019 Canonical Ltd.

# Authors
#  Jeff Lane <jeff@ubuntu.com>

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3,
# as published by the Free Software Foundation.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

MAAS_FILE="/etc/installed-by-maas"
MIN_VERSION="2.0"

# Is the file there?
if [ -s $MAAS_FILE ]; then
    maas_version=$(cat $MAAS_FILE)
    echo "$maas_version"
else
    echo "ERROR: This system does not appear to have been installed by MAAS"
    echo "ERROR: " "$(ls -l $MAAS_FILE 2>&1)"
    exit 1
fi

#is the version appropriate
exit "$(dpkg --compare-versions "$maas_version" "ge" $MIN_VERSION)"
