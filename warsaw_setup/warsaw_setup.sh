#!/bin/bash

if ! ./eula_reader; then
  exit 1
fi

deb_installer=(warsaw_*.deb)
rpm_installer=(warsaw-*.rpm)
pub_key=(*-RPM-GPG-KEY)

if [[ -e $deb_installer ]]; then
  installer=$deb_installer
elif [[ -e $rpm_installer ]]; then
  installer=$rpm_installer
else
  exit 2
fi

if type snap-store 2>/dev/null 1>&2; then
  snap-store --local-filename $installer
  exit $?
fi

if type gdebi-gtk 2>/dev/null 1>&2; then
  gdebi-gtk $installer
  exit $?
fi

if type qapt-deb-installer 2>/dev/null 1>&2; then
  qapt-deb-installer rcode_check $installer
  exit $?
fi

if type software-center 2>/dev/null 1>&2; then
  software-center $installer
  exit $?
fi

if type plasma-discover 2>/dev/null 1>&2; then
  plasma-discover $installer
  exit $?
fi

if type yast2 2>/dev/null 1>&2; then
  echo rpmkeys --import $pub_key > inst.sh
  echo yast2 sw_single $installer >> inst.sh
  chmod +x inst.sh
  if type xdg-su 2>/dev/null 1>&2; then
    xdg-su -c "./inst.sh" || rm inst.sh
  elif type gnomesu 2>/dev/null 1>&2; then
    gnomesu -c "./inst.sh" || rm inst.sh
  else
    sudo "./inst.sh" || rm inst.sh
  fi
  exit $?
fi

if type /sbin/yast2 2>/dev/null 1>&2; then
  echo rpmkeys --import $pub_key > inst.sh
  echo /sbin/yast2 sw_single $installer >> inst.sh
  chmod +x inst.sh
  if type xdg-su 2>/dev/null 1>&2; then
    xdg-su -c "./inst.sh" || rm inst.sh
  elif type gnomesu 2>/dev/null 1>&2; then
    gnomesu -c "./inst.sh" || rm inst.sh
  else
    sudo "./inst.sh" || rm inst.sh
  fi
  exit $?
fi

if type gnome-software 2>/dev/null 1>&2; then
  gnome-software --local-filename=$installer
  exit $?
fi

if type gpk-install-local-file 2>/dev/null 1>&2; then
  gpk-install-local-file $installer
  exit $?
fi

if type dpkg 2>/dev/null 1>&2; then
  sudo dpkg -i $installer
  exit $?
fi

exit 3
