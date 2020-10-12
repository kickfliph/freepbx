# freepbx
Automated FreePBX bash script using:

* mongodb-org-4.4

* Node.js 12

* mariadb-connector-odbc-3.1.9-debian-buster-amd64

* dahdi-linux-complete-3.1.0+3.1.0

* asterisk-17-current

  On Add-ons select chan_ooh323 and format_mp3  as shown below
  
  ![](/images/install-asterisk-menu01.png)
  
  On Core Sound Packages, select the formats of Audio packets like below
  
  ![](/images/install-asterisk-menu02.webp)
  
  For Music On Hold, select the following minimal modules

  ![](/images/install-asterisk-menu03.webp)
  
  On Extra Sound Packages select as shown below
  
  ![](/images/install-asterisk-menu04.webp)

  Enable app_macro under Applications menu

  ![](/images/asterisk-enable-app_macro_menu04.webp)

* Freepbx 15
* Certbot
* Nginx
* fail2ban
* voipbl

This scritp has been proven on debian 10
