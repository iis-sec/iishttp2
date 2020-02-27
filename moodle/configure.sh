#!/bin/bash

if [ ! -f /config-stat.txt ]; then
  STAT=$(stat -t /envs)
  echo ${STAT} > /config-stat.txt
  FIRST_RUN="yes"
fi

OLD_STAT=$(cat /config-stat.txt)
NEW_STAT=$(stat -t /envs)
if [ "${OLD_STAT}" != "${NEW_STAT}" ] || [ "${FIRST_RUN}" == "yes" ]; then
  echo ${NEW_STAT} > /config-stat.txt


  ALL_FILES=""

  if [ -f /settings.scsv ]; then
    rm /settings.scsv
  fi

  source /envs/common.env
  export common_vars=$(for variable in $(cat /envs/common.env | cut -f -1 -d '='); do echo -n \$${variable}; done)

  if [ ! -d "/var/lib/mysql/moodle" ]; then
    pushd /var/www/html
    sudo -u www-data /usr/bin/php admin/cli/install_database.php --adminpass=${MOODLE_PASSWORD} --adminemail=${ADMIN_EMAIL} --agree-license --fullname=${SITE_FULLNAME} --shortname=${SITE_SHORTNAME}
    popd
  fi

  for config in /envs/*.env; do
    set -a
    source ${config}
    set +a
    name=$(grep MOODLE_PHP_CONFIG ${config} | cut -f 1 -d '=' | sed 's/_MOODLE_PHP_CONFIG//g')
    filevar=${name}_MOODLE_PHP_CONFIG
    for file in ${!filevar}; do
      file=$(echo -n ${file} | tr -d '\r')
      variables=$(echo -n \'; echo -n ${common_vars}; for variable in $(cat ${config} | cut -f -1 -d '='); do echo -n \$${variable}; done; echo -n \')
      template=$(echo -n /config/template-${file} | tr -d '\r')
      output=$(echo -n /config/${file} | tr -d '\r')
      cat ${template-config} | sed "s/^M//g" | tr -d '\r' | envsubst ${variables} > ${output}
      ALL_FILES="${ALL_FILES} ${output}"
    done
  done

  cat ${ALL_FILES} | sed "s/^M//g" | tr -d '\r' | sed 's/^;;$//g' | egrep -v '^$' >> /settings.scsv

  if [ -f /moosh-settings.sh ]; then
    rm /moosh-settings.sh
  fi

  if [ -f /moodle-default-settings.php ]; then
    rm /moodle-default-settings.php
  fi

  echo '<?php' > /moodle-default-settings.php
  while read line; do
    plugin=$( echo ${line} | sed "s/^M//g" | tr -d '\r' | cut -f 1 -d ';' | sed s/\'//g)
    setting=$(echo ${line} | sed "s/^M//g" | tr -d '\r'  | cut -f 2 -d ';' | sed s/\'//g)
    value=$(echo ${line} | sed "s/^M//g" | tr -d '\r' | cut -f 3 -d ';')
    echo /moosh/moosh.php -n config-set ${setting} ${value} "${plugin}" | sed "s/^M//g" | tr -d '\r' | sed "s/''$//g" | egrep -v '^/moosh/moosh.php -n config-set$' >> /moosh-settings.sh
    echo "\$default['"${plugin}"']['"${setting}"'] = "${value}";" | sed "s/^M//g" | tr -d '\r' | sed "s/''$//g"  >> /moodle-default-settings.php
  done < settings.scsv

  cat /config/moosh*.sh | tr -d '\r' >> /moosh-settings.sh

  chmod a+x /moosh-settings.sh
  pushd /var/www/html
  /moosh-settings.sh
  popd
  
  cp /moodle-default-settings.php /var/www/html/local/defaults.php

  pushd /var/www/html/mod/hvp/
  echo "Downloading and installing default h5p activity librarieis"
  php autoinstallhvplibs.php
  rm autoinstallhvplibs.php
  echo "h5p libraries installed"
  popd

  ALL_CAPABILITY_SETTINGS=""

  for config in /envs/*.env; do
    set -a
    source ${config}
    set +a
    name=$(grep MOODLE_PHP_CAPABILITY ${config} | cut -f 1 -d '=' | sed 's/_MOODLE_PHP_CAPABILITY//g')
    if [ -z "$name" ]
	then
		continue
	fi
    filevar=${name}_MOODLE_PHP_CAPABILITY
    for file in ${!filevar}; do
      file=$(echo -n ${file} | tr -d '\r')
      variables=$(echo -n \'; echo -n ${common_vars}; for variable in $(cat ${config} | cut -f -1 -d '='); do echo -n \$${variable}; done; echo -n \')
      capability=$(echo -n /config/capability-${file} | tr -d '\r')
      output=$(echo -n /config/${file} | tr -d '\r')
      cat ${capability-config} | sed "s/^M//g" | tr -d '\r' | envsubst ${variables} > ${output}
      ALL_CAPABILITY_SETTINGS="${ALL_CAPABILITY_SETTINGS} ${output}"
    done
  done

  if [[ !  -z  ${ALL_CAPABILITY_SETTINGS}  ]] 
    then  
      cat ${ALL_CAPABILITY_SETTINGS} | sed "s/^M//g" | tr -d '\r' | sed 's/^;;$//g' | egrep -v '^$' >> /capability.scsv

      while read line; do
         if [ -z "$line" ]
           then
             continue
           else
             role=$( echo ${line} | sed "s/^M//g" | tr -d '\r' | cut -f 1 -d ';' | sed s/\'//g)
             capability=$(echo ${line} | sed "s/^M//g" | tr -d '\r'  | cut -f 2 -d ';' | sed s/\'//g)
             setting=$(echo ${line} | sed "s/^M//g" | tr -d '\r' | cut -f 3 -d ';')
             environment=$(echo ${line} | sed "s/^M//g" | tr -d '\r' | cut -f 4 -d ';')
             echo /moosh/moosh.php -n role-update-capability ${role} ${capability} ${setting} ${environment} | sed "s/^M//g" | tr -d '\r' | sed "s/''$//g" | egrep -v '^/moosh/moosh.php -n config-set$' >> /moosh-capability.sh
         fi
      done < capability.scsv
  
      if [ -f "/moosh-capability.sh" ]
        then
          chmod a+rx /moosh-capability.sh
          pushd /var/www/html
          /moosh-capability.sh
          popd
      fi
  fi
fi
