#!/bin/bash
set -e

BUILD_HTTPPORT=$((8000 + $UID))
TRY_HTTPPORT=$((BUILD_HTTPPORT + 100))
TESTS_HTTPPORT=$((BUILD_HTTPPORT + 200))

NAME=$1
if [ -z "$PY" ] ; then
    PY=python2.6
fi
echo Using \"$PY\" interpreter for python
if [ -z "$REPO_PATH" ] ; then
    REPO_PATH=build
fi
if [ -z "$NAME" ] ; then
    echo "You must have a project name"
    exit
fi

test -e "$NAME" && echo "a file called $NAME already exists" && exit

$PY `which virtualenv` $NAME
cd $NAME
for i in buildbot twisted tools buildbotcustom buildbot-configs puppet-manifests ; do
    echo Cloning $i
    hg clone http://hg.mozilla.org/${REPO_PATH}/$i
done

echo Cloning braindump
hg clone http://hg.mozilla.org/build/braindump

VENV_PY=$PWD/bin/$(basename $PY)
BUILDBOT=$PWD/bin/buildbot
echo Running python scripts using "$VENV_PY"
echo Installing Twisted
(cd twisted && $VENV_PY setup.py install)
echo Installing Buildbot Master
(cd buildbot/master && $VENV_PY setup.py install)
echo Installing Buildbot Slave
(cd buildbot/slave && $VENV_PY setup.py install)

#configure buildbotcustom to be in the path for virtualenv
pwd > lib/$PY/site-packages/buildbotcustom.pth
echo $(pwd)/tools/lib/python > lib/$PY/site-packages/tools.pth

cat > master.json << EOF
[
  {
    "environment": "staging",
    "hostname": "$(hostname)",
    "name": "build-master",
    "release_branches": ["mozilla-1.9.2", "mozilla-beta"],
    "mobile_release_branches": ["mozilla-beta"],
    "role": "build",
    "pb_port": $(($BUILD_HTTPPORT + 1000)),
    "http_port": $BUILD_HTTPPORT,
    "ssh_port": $(($BUILD_HTTPPORT - 1000))
  },
  {
    "environment": "staging",
    "hostname": "$(hostname)",
    "name": "try-master",
    "role": "try",
    "pb_port": $(($TRY_HTTPPORT + 1000)),
    "http_port": $TRY_HTTPPORT,
    "ssh_port": $(($TRY_HTTPPORT - 1000))
  },
  {
    "environment": "staging",
    "hostname": "$(hostname)",
    "name": "test-master",
    "role": "tests",
    "pb_port": $(($TESTS_HTTPPORT + 1000)),
    "http_port": $TESTS_HTTPPORT,
    "ssh_port": $(($TESTS_HTTPPORT - 1000))
  }

]
EOF

cat > Makefile << EOF
checkconfig-all:
	(cd build-master && $BUILDBOT checkconfig)
	(cd try-master && $BUILDBOT checkconfig)
	(cd test-master && $BUILDBOT checkconfig)

EOF

for i in build try "test" ; do
	echo "Creating $i-master"
    (cd buildbot-configs && $VENV_PY setup-master.py -b $BUILDBOT -j ../master.json ../$i-master $i-master)
	(cd $i-master && ln -s ../buildbot-configs/Makefile.master Makefile && ln -s . master)
	(cd $i-master && rm -f master.cfg)
done

for i in build try ; do
	(cd $i-master && ln -s ../buildbot-configs/mozilla/universal_master_sqlite.cfg master.cfg)
done
(cd test-master && ln -s ../buildbot-configs/mozilla-tests/universal_master_sqlite.cfg master.cfg)


echo build-master: http://$(hostname):$BUILD_HTTPPORT/
echo try-master: http://$(hostname):$TRY_HTTPPORT/
echo test-master: http://$(hostname):$TESTS_HTTPPORT/
echo "run 'cd $NAME; source bin/activate"
