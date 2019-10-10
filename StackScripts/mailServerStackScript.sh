#!/bin/bash
# This block defines the variables that the user of the script needs to input
# when deploying using this script.
#
#<UDF name="hostname" label="The hostname for the new Linode.">
#<UDF name="fqdn" label="The new Linode's Fully Qualified Domain Name">
#<UDF name="username" label="username">
#<UDF name="password" label="The password for username">
#

# This sets the variable $IPADDR to the IP address the new Linode receives.
IPADDR=$(/sbin/ifconfig eth0 | awk '/inet / { print $2 }' | sed 's/addr://')

# This updates the packages on the system from the distribution repositories.
DEBIAN_FRONTEND=noninteractive apt-get update -y -q  && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -q

# This section sets the hostname.
echo $HOSTNAME > /etc/hostname
hostname -F /etc/hostname

# This section sets the Fully Qualified Domain Name (FQDN) in the hosts file.
echo $IPADDR $FQDN $HOSTNAME >> /etc/hosts

# add user with password
adduser --quiet --disabled-password --shell /bin/bash --home /home/$USERNAME $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd

# create ssl cert
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/ssl-mail.key -out /etc/ssl/certs/ssl-mail.pem

# install packages
debconf-set-selections <<< "postfix postfix/mailname string $HOSTNAME"
debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
apt-get install -y postfix
apt-get install postfix-policyd-spf-python postfix-pcre dovecot-core dovecot-imapd dovecot-pop3d dovecot-lmtpd opendkim opendkim-tools

# get postfix config files
mv /etc/postfix/master.cf /etc/postfix/master.cf.bak
mv /etc/postfix/main.cf /etc/postfix/main.cf.bak
wget https://raw.githubusercontent.com/ctdurazo/LinodeStuff/blob/master/mailServerConfs/postfix/master.cf -O /etc/postfix/master.cf #TODO
wget https://raw.githubusercontent.com/ctdurazo/LinodeStuff/blob/master/mailServerConfs/postfix/main.cf -O /etc/postfix/main.cf #TODO
sed -i "s/christiandurazo.dev/$HOSTNAME/g" /etc/postfix/main.cf

# get dovecot config files
mv /etc/dovecot/dovecot.conf /etc/dovecot/dovecot.conf.bak
wget https://raw.githubusercontent.com/ctdurazo/LinodeStuff/blob/master/mailServerConfs/dovecot/dovecot.conf -O /etc/dovecot/dovecot.conf #TODO

# get opendkim config files
mv /etc/opendkim.conf /etc/opendkim.conf.bak
mv /etc/default/opendkim
wget https://raw.githubusercontent.com/ctdurazo/LinodeStuff/blob/master/mailServerConfs/opendkim/opendkim.conf -O /etc/opendkim.conf #TODO
wget https://raw.githubusercontent.com/ctdurazo/LinodeStuff/blob/master/mailServerConfs/opendkim/opendkim -O /etc/default/opendkim #TODO

# add aliases to /etc/aliases
echo "mailer-daemon: postmaster" >> /etc/aliases
echo "postmaster: root" >> /etc/aliases
echo "nobody: root" >> /etc/aliases
echo "hostmaster: root" >> /etc/aliases
echo "usenet: root" >> /etc/aliases
echo "news: root" >> /etc/aliases
echo "webmaster: root" >> /etc/aliases
echo "www: root" >> /etc/aliases
echo "ftp: root" >> /etc/aliases
echo "abuse: root" >> /etc/aliases
echo "security: root" >> /etc/aliases
echo "root: $USERNAME" >> /etc/aliases

# set permissions and make directories
chmod u=rw,go=r /etc/opendkim.conf
#mkdir /etc/opendkim
#mkdir /etc/mail
mkdir /etc/{opendkim,mail}
chown -R opendkim:opendkim /etc/opendkim
mkdir /var/log/dkim-filter
touch /var/log/dkim-filter/dkim-stats
chown opendkim:opendkim /var/log/dkim-filter/
chown opendkim:opendkim /var/log/dkim-filter/dkim-stats
echo $HOSTNAME $HOSTNAME:mail:/etc/mail/dkim.key >> /etc/opendkim/KeyTable
echo \* $HOSTNAME >> /etc/opendkim/SigningTable
echo 127.0.0.1 >> /etc/opendkim/TrustedHosts
mkdir /var/spool/postfix/opendkim
chown opendkim:postfix /var/spool/postfix/opendkim

# create dkim keys
opendkim-genkey -s mail -d `hostname`
mv mail.private dkim.key
mv * /etc/mail/
chown opendkim:opendkim /etc/mail/*
chmod 600 /etc/mail/*

# create flush.sh
touch flush.sh
echo "postfix flush" >> flush.sh
echo "/etc/init.d/postfix restart" >> flush.sh

# create mail logs
touch /var/log/mail.log
touch /var/log/mail.err
sudo chmod a+w /var/log/mail*

# create backup dir and crontabs
mkdir /var/backup/
( crontab -l ; echo "0 1 * * * /root/flush.sh" ) | crontab -

# create ssh keys
ssh-keygen -f ~/.ssh/id_rsa -P ""

# update and restart services
adduser postfix opendkim
newaliases
systemctl restart postfix
systemctl restart dovecot
systemctl restart opendkim
