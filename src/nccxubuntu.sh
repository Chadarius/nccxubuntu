#!/bin/bash
#------------------------------------------------------------------------------
# Chad Sutton <casutton@noctrl.edu> NCC Ubuntu Scripts
# 	This is a script for use with Vagrant and VirtualBox
#	at North Central College. 
#	This script is licensed under GPL 3.0
#------------------------------------------------------------------------------

# Script_path for relative paths
script_path=`dirname "$0"`
script_name=`basename "$0"`

# Pull in function libraries (should be a ./lib directory for libraries)
for f in $(ls $script_path/lib); 
    do source $script_path/lib/$f; 
done

# Pull in config settings (should be a ./conf directory for config files)
# Conf file should be named the same as the bash script e.g. ./conf/template-script.sh.conf
if [ -f "${script_path}/conf/${script_name}.conf" ]; then
	source ${script_path}/conf/${script_name}.conf
fi

# Set timezone
echo -e "America/Chicago" | sudo tee /etc/timezone
sudo dpkg-reconfigure --frontend noninteractive tzdata
echo "NTP=time.nccnet.noctrl.edu" |sudo tee -a /etc/systemd/timesyncd.conf

# Update repos and packages
sudo apt-get update
#sudo apt-get upgrade -y
sudo DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade

sudo DEBIAN_FRONTEND=noninteractive apt-get install build-essential debconf-utils checkinstall dh-make \
	fakeroot git devscripts libxml-parser-perl cdbs avahi-daemon \
	check cvs subversion git-core git gparted mercurial \
	linux-headers-$(uname -r) nano open-vm-tools aptitude curl p7zip-rar zip \
	unzip rar unrar uudeview p7zip mpack lhasa arj cabextract \
	file-roller ldap-utils sssd sssd-ldap sssd-tools libpam-mount \
	openjdk-8-jre openjdk-8-jdk ant ivy cifs-utils zerofree davfs2 lvm2 \
	-y

# Install Oracle Java
sudo add-apt-repository ppa:webupd8team/java -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install oracle-java8-installer -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install oracle-java8-set-default

# Update ldap.conf

if [ ! -f "/etc/ldap/ldap.conf.bak" ]; then
    sudo cp "/etc/ldap/ldap.conf" "/etc/ldap/ldap.conf.bak"
fi

# Add last line to ldap.conf
sudo sed -i '$ a TLS_REQCERT allow' /etc/ldap/ldap.conf

# Configure eDir CA
echo "Downloading eDirectory CA certificate"
edir_ca

###############################################################################
# sssd.conf as variable
sssd_conf=$(cat <<EOF
[sssd]
config_file_version = 2
reconnection_retries = 3
sbus_timeout = 30
services = nss,pam
domains = default
; domains = LOCAL,LDAP

[nss]
filter_groups = root
filter_users = root
reconnection_retries = 3
; entry_cache_nowait_percentage = 300

[pam]
reconnection_retries = 3
[domain/default]
ldap_uri = $ldap_uri
ldap_search_base = $ldap_search_base
ldap_schema = rfc2307bis
id_provider = ldap
ldap_user_uuid = entryuuid
ldap_group_uuid = entryuuid
ldap_id_use_start_tls = True
enumerate = False
cache_credentials = True
ldap_tls_cacertdir = /etc/ssl/certs/
ldap_tls_cacert = $ldap_tls_cacert
ldap_tls_reqcert = demand
chpass_provider = ldap
auth_provider = ldap
ldap_user_member_of = groupMembership
ldap_group_member = member
access_provider = simple
#simple_allow_groups = $simple_allow_groups
ldap_user_search_base = $ldap_user_search_base
ldap_default_bind_dn = $ldap_default_bind_dn
ldap_default_authtok_type = password
ldap_default_authtok = $ldap_default_authtok
EOF
)
# end of sssd.conf as variable
###############################################################################

# write /etc/sssd/sssd.conf
echo -e "${sssd_conf}" |sudo tee /etc/sssd/sssd.conf
# set to secure file so only root can read it
sudo chmod 0600 /etc/sssd/sssd.conf

# Create /Users link to /home to be compatible with Mac user home dir setting in eDirectory
sudo ln -s /home /Users


###############################################################################
# /usr/share/pam-configs/my_mkhomedir file in variable
# Used to create a home directory automatically upon login for users
my_mkhomedir=$(cat <<EOF
Name: activate mkhomedir
Default: yes
Priority: 900
Session-Type: Additional
Session:
        required	pam_mkhomedir.so umask=0022 skel=/etc/skel
EOF
)
# end of my_mkhomedir
###############################################################################

# write /usr/share/pam-configs/my_mkhomedir
echo -e "${my_mkhomedir}" |sudo tee /usr/share/pam-configs/my_mkhomedir

###############################################################################
# /usr/share/pam-configs/my_groups as variable
my_groups=$(cat <<EOF 
Name: activate /etc/security/group.conf
Default: yes
Priority: 900
Auth-Type: Primary
Auth:
        required		pam_group.so use_first_pass
EOF
)
# end of mygroups
###############################################################################

# write /usr/share/pam-configs/my_groups
echo -e "${my_groups}" | sudo tee /usr/share/pam-configs/my_groups

# Add config lines to end of /etc/security/group.conf
sudo sed -i '$ a *;*;%ITS;Al0000-2400;dialout,fax,cdrom,floppy,tape,audio,dip,video,scanner,plugdev,syslog,,lpadmin,adm,sudo,sambashare,www-data,backup,operator,users,syslog,netdev,davfs2' /etc/security/group.conf
sudo sed -i '$ a *;*;*;Al0000-2400;dialout,fax,cdrom,floppy,tape,audio,dip,video,scanner,plugdev,lpadmin,sambashare,users,davfs2' /etc/security/group.conf

# Configure CIFS to allow mapping to older SMB servers
# backup file
sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.bak
# Please this line under the workgroup = WORKGROUP line in smb.conf
sudo sed -i '/workgroup = WORKGROUP/ a \ \ \ client use spnego = no' /etc/samba/smb.conf


###############################################################################
# /etc/security/pam_mount.conf.xml as variable
pam_mount_conf_xml=$(cat <<EOF
<?xml version="1.0" encoding="utf-8" ?>
<!DOCTYPE pam_mount SYSTEM "pam_mount.conf.xml.dtd">
<!--
	See pam_mount.conf(5) for a description.
-->
<pam_mount>
	<!-- debug should come before everything else,
	since this file is still processed in a single pass
	from top-to-bottom -->
	<debug enable="0" />
	<!-- Volume definitions -->
	<!-- pam_mount parameters: General tunables -->
	<luserconf name=".pam_mount.conf.xml" />
	<!-- Note that commenting out mntoptions will give you the defaults.
	     You will need to explicitly initialize it with the empty string
	     to reset the defaults to nothing. -->
	<!--
	<mntoptions allow="nosuid,nodev,loop,encryption,fsck,nonempty,allow_root,allow_other" />
	<mntoptions deny="suid,dev" />
	<mntoptions allow="*" />
	<mntoptions deny="*" />
	-->
	<mntoptions allow="*" />
	<!-- 
	<mntoptions require="nosuid,nodev" />
	-->
	<logout wait="2000" hup="yes" term="yes" kill="yes" />
	<!-- pam_mount parameters: Volume-related -->
	<mkmountpoint enable="1" remove="true" />
	<volume
	        pgrp="ITS"
	        options="sec=ntlm,vers=1.0,noserverino,nosuid,nodev,dir_mode=0700,file_mode=0700,username=%(USER),vers=1.0,cache=strict,uid=%(USERUID),forceuid,gid=%(USERGID),forcegid"
	        server="oesfs01.nccnet.noctrl.edu"
	        path="home/%(USER)"
	        mountpoint="/media/%(USER)/f-drive"
	        fstype="cifs"
	/>
	<volume
	        pgrp="Admstr-grp"
	        options="sec=ntlm,vers=1.0,noserverino,nosuid,nodev,dir_mode=0700,file_mode=0700,username=%(USER),vers=1.0,cache=strict,uid=%(USERUID),forceuid,gid=%(USERGID),forcegid"
	        server="oesfs01.nccnet.noctrl.edu"
	        path="home/%(USER)"
	        mountpoint="/media/%(USER)/f-drive"
	        fstype="cifs"
	/>
	<volume
	        pgrp="Faclty-grp"
	        options="sec=ntlm,vers=1.0,noserverino,nosuid,nodev,dir_mode=0700,file_mode=0700,username=%(USER),vers=1.0,cache=strict,uid=%(USERUID),forceuid,gid=%(USERGID),forcegid"
	        server="oesfs07.nccnet.noctrl.edu"
	        path="home/%(USER)"
	        mountpoint="/media/%(USER)/f-drive"
	        fstype="cifs"
	/>
	<volume
	        pgrp="stdnts-grp"
	        options="sec=ntlm,vers=1.0,noserverino,nosuid,nodev,dir_mode=0700,file_mode=0700,username=%(USER),vers=1.0,cache=strict,uid=%(USERUID),forceuid,gid=%(USERGID),forcegid"
	        server="studhome.nccnet.noctrl.edu"
	        path="studhome/%(USER)"
	        mountpoint="/media/%(USER)/f-drive"
	        fstype="cifs"
	/>
	<volume
	        user="*"
	        options="sec=ntlm,vers=1.0,noserverino,dir_mode=0700,file_mode=0700,username=%(USER)"
	        server="oesfs03.nccnet.noctrl.edu"
	        path="personalweb/faculty/%(USER)"
	        mountpoint="/media/%(USER)/w-drive"
	        fstype="cifs"
	/>
	<volume
	        user="*"
	        options="sec=ntlm,vers=1.0,noserverino,dir_mode=0700,file_mode=0700,username=%(USER)"
	        server="oesfs02.nccnet.noctrl.edu"
	        path="coursefiles"
	        mountpoint="/media/%(USER)/k-drive"
	        fstype="cifs"
	/>
	<volume
	        user="*"
	        options="sec=ntlm,vers=1.0,noserverino,dir_mode=0700,file_mode=0700,username=%(USER)"
	        server="oesfs06.nccnet.noctrl.edu"
	        path="deptfiles"
	        mountpoint="/media/%(USER)/n-drive"
	        fstype="cifs"
	/>
	<volume
	        pgrp="ITS"
	        options="sec=ntlm,vers=1.0"
	        server="oesdev01.nccnet.noctrl.edu"
	        path="dev"
	        mountpoint="/media/%(USER)/oesdev01"
	        fstype="cifs"
	/>
</pam_mount>
EOF
)
# end of /etc/security/pam_mount.conf.xml
###############################################################################

if [ ! -f "/etc/security/pam_mount.conf.xml.bak" ]; then
    sudo cp /etc/security/pam_mount.conf.xml /etc/security/pam_mount.conf.xml.bak
fi

echo -e "${pam_mount_conf_xml}" | sudo tee /etc/security/pam_mount.conf.xml

# Update /etc/ssh/ssh_config to enable pam_mount
if [ ! -f "/etc/ssh/ssh_config.bak" ];then
    sudo cp /etc/ssh/ssh_config /etc/ssh/ssh_config.bak
fi
sudo sed -i '$ a ChallengeResponseAuthentication no' /etc/ssh/ssh_config
sudo sed -i '$ a PasswordAuthentication yes' /etc/ssh/ssh_config

# Update PAM files
sudo DEBIAN_FRONTEND=noninteractive pam-auth-update
sudo service sssd restart

#Configure Login Screen
echo Configure LightDM Login Screen

lightdmncc=$(cat <<EOF
[SeatDefaults]
greeter-hide-users=true
greeter-show-manual-login=true
allow-guest=false
EOF
)

echo -e "${lightdmncc}" |sudo tee /etc/lightdm/lightdm.conf.d/50-ncc-custom-config.conf


