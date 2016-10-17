#!/bin/bash
APP_NAME="<%= appName %>"

# utilities
gyp_rebuild_inside_node_modules () {
  for npmModule in ./*; do
    cd $npmModule

    isBinaryModule="no"
    # recursively rebuild npm modules inside node_modules
    check_for_binary_modules () {
      if [ -f binding.gyp ]; then
        isBinaryModule="yes"
      fi

      if [ $isBinaryModule != "yes" ]; then
        if [ -d ./node_modules ]; then
          cd ./node_modules
          for module in ./*; do
            cd $module
            check_for_binary_modules
            cd ..
          done
          cd ../
        fi
      fi
    }

    check_for_binary_modules

    if [ $isBinaryModule = "yes" ]; then
      echo " > $npmModule: npm install due to binary npm modules"
      rm -rf node_modules
      if [ -f binding.gyp ]; then
        sudo npm install
        sudo node-gyp rebuild || :
      else
        sudo npm install
      fi
    fi

    cd ..
  done
}

rebuild_binary_npm_modules () {
  for package in ./*; do
    if [ -d $package/node_modules ]; then
      cd $package/node_modules
        gyp_rebuild_inside_node_modules
      cd ../../
    elif [ -d $package/main/node_module ]; then
      cd $package/node_modules
        gyp_rebuild_inside_node_modules
      cd ../../../
    elif [ -d $package ]; then # Meteor 1.3
      cd $package
        rebuild_binary_npm_modules
      cd ..
    fi
  done
}

revert_app () {
  if [[ -d old_app ]]; then
    sudo rm -rf app
    sudo mv old_app app
    sudo systemctl restart <%= appName %>.service || :
    echo "Latest deployment failed! Reverted back to the previous version." 1>&2
    exit 1
  else
    echo "App did not pick up! Please check app logs." 1>&2
    exit 1
  fi
}


# logic
set -e

TMP_DIR=/opt/<%= appName %>/tmp
BUNDLE_DIR=${TMP_DIR}/bundle

cd ${TMP_DIR}
sudo rm -rf bundle
sudo tar xvzf bundle.tar.gz > /dev/null
sudo chmod -R +x *
sudo chown -R ${USER} ${BUNDLE_DIR}

# rebuilding fibers
cd ${BUNDLE_DIR}/programs/server

if [ -d ./npm ]; then
  cd npm
  if [ -d ./node_modules ]; then # Meteor 1.3
    cd node_modules
    rebuild_binary_npm_modules
    cd ..
  else
    rebuild_binary_npm_modules
  fi
  cd ../
fi

if [ -d ./node_modules ]; then
  cd ./node_modules
  gyp_rebuild_inside_node_modules
  cd ../
fi

if [ -f package.json ]; then
  # support for 0.9
  sudo npm install
else
  # support for older versions
  sudo npm install fibers
  sudo npm install bcrypt
fi

cd /opt/<%= appName %>/

# remove old app, if it exists
if [ -d old_app ]; then
  sudo rm -rf old_app
fi

## backup current version
if [[ -d app ]]; then
  sudo mv app old_app
fi

sudo mv tmp/bundle app

#wait and check
#echo "Waiting for MongoDB to initialize. (5 minutes)"
echo "Waiting for MongoDB to initialize. (1 minute)"
. /opt/<%= appName %>/config/env.sh
#wait-for-mongo ${MONGO_URL} 60000
#wait-for-mongo ${MONGO_URL} 300000

sudo systemctl restart ${APP_NAME}.service

# restart app
# sudo stop <%= appName %> || :
# sudo start <%= appName %> || :

# check upstart
# UPSTART=0
# if [ -x /sbin/initctl ] && /sbin/initctl version 2>/dev/null | /bin/grep -q upstart; then
#   UPSTART=1
# fi
#
# # restart app
# echo "Restarting the app"
# if [[ $UPSTART == 1 ]] ; then
#   sudo stop $APP_NAME || :
#   sudo start $APP_NAME || :
# else
#   sudo systemctl restart ${APP_NAME}.service
# fi

echo "Waiting for <%= deployCheckWaitTime %> seconds while app is booting up"
sleep <%= deployCheckWaitTime %>

echo "Checking is app booted or not?"
curl localhost:${PORT} || revert_app

# chown to support dumping heapdump and etc
sudo chown -R meteoruser app
