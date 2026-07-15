#!/bin/bash

EXT_STORE="/opt/guacamole"
GUAC_EXT="/config/guacamole/extensions"
TOMCAT_LOG="/config/log/tomcat"
CHANGES=false

# Create user
PUID=${PUID:-99}
PGID=${PGID:-100}

groupmod -o -g "$PGID" abc
usermod -o -u "$PUID" abc

echo "----------------------"
echo "User UID: $(id -u abc)"
echo "User GID: $(id -g abc)"
echo "----------------------"

chown -R abc:abc /config
chown -R abc:abc /opt/tomcat /var/run/tomcat /var/lib/tomcat

# Check if logback.xml exists and set the log level based on LOGBACK_LEVEL value
if [ ! -f "$GUACAMOLE_HOME"/logback.xml ]; then
  unzip -o -j /opt/guacamole/guacamole.war WEB-INF/classes/logback.xml -d "$GUACAMOLE_HOME" > /dev/null
fi
sed -i 's/ level="[^"]*"/ level="'$LOGBACK_LEVEL'"/' "$GUACAMOLE_HOME"/logback.xml

OPTMYSQL=${OPT_MYSQL:-N}

# Check if properties file exists. If not, copy in the starter database
if [ -f /config/guacamole/guacamole.properties ]; then
  echo "Using existing properties file."
  if [ ! -d "$TOMCAT_LOG" ]; then
    echo "Creating log directory."
    mkdir -p "$TOMCAT_LOG"
    chown -R abc:abc "$TOMCAT_LOG"
  fi
else
  echo "Creating properties from template."
  mkdir -p "$GUAC_EXT" /config/guacamole/lib "$TOMCAT_LOG"
  cp /etc/firstrun/templates/* /config/guacamole
  chown -R abc:abc /config/guacamole "$TOMCAT_LOG"
  if [ "$OPTMYSQL" = "Y" ] && [ -f /etc/firstrun/mariadb.sh ]; then
    echo "Creating Database folders"
    mkdir -p /config/databases
    chown abc:abc /config/databases
  fi
  PW=$(pwgen -1snc 32)
  sed -i -e 's/some_password/'$PW'/g' /config/guacamole/guacamole.properties
  CHANGES=true
fi

# Check if extensions files exists. Copy or upgrade if necessary.
OPTMYSQLEXT=${OPT_MYSQL_EXTENSION:-N}
if [ "$OPTMYSQL" = "Y" ] || [ "$OPTMYSQLEXT" = "Y" ]; then
  # MySQL extension paths - updated for Guacamole 1.x directory structure
  MYSQL_EXT_SRC="$EXT_STORE/extensions/guacamole-auth-jdbc/mysql"
  MYSQL_JDBC_SRC="$EXT_STORE/drivers/mysql-jdbc.jar"

  if compgen -G "$GUAC_EXT/*jdbc-mysql*.jar" > /dev/null; then
    oldMysqlFiles=( "$GUAC_EXT"/*jdbc-mysql*.jar )
    newMysqlFiles=( "$MYSQL_EXT_SRC"/*jdbc-mysql*.jar )

    if diff ${oldMysqlFiles[0]} ${newMysqlFiles[0]} >/dev/null ; then
      echo "Using existing MySQL extension."
      if [ ! -d /config/mysql-schema ]; then
        mkdir /config/mysql-schema
        cp -R "$MYSQL_EXT_SRC"/schema/* /config/mysql-schema
        CHANGES=true
      fi
    else
      echo "Upgrading MySQL extension."
      rm "$GUAC_EXT"/*jdbc-mysql*.jar
      cd /config/guacamole/lib
      rm mysql-connector*.jar
      cp "$MYSQL_EXT_SRC"/*jdbc-mysql*.jar "$GUAC_EXT"
      cp "$MYSQL_JDBC_SRC" /config/guacamole/lib/mysql-jdbc.jar
      rm -R /config/mysql-schema/*
      cp -R "$MYSQL_EXT_SRC"/schema/* /config/mysql-schema
      CHANGES=true
    fi
  else
    echo "Copying MySQL extension."
    mkdir -p "$GUAC_EXT" /config/guacamole/lib /config/mysql-schema
    cp "$MYSQL_EXT_SRC"/*jdbc-mysql*.jar "$GUAC_EXT"
    cp "$MYSQL_JDBC_SRC" /config/guacamole/lib/mysql-jdbc.jar
    cp -R "$MYSQL_EXT_SRC"/schema/* /config/mysql-schema
    CHANGES=true
  fi
elif [ "$OPTMYSQL" = "N" ] || [ "$OPTMYSQLEXT" = "N" ]; then
  if [ -f "$GUAC_EXT"/*jdbc-mysql*.jar ]; then
    echo "Removing MySQL extension."
    rm "$GUAC_EXT"/*jdbc-mysql*.jar
    cd /config/guacamole/lib
    rm -f mysql-connector*.jar mysql-jdbc.jar
    rm -R /config/mysql-schema
  fi
fi

OPTSQLSERVER=${OPT_SQLSERVER:-N}
if [ "$OPTSQLSERVER" = "Y" ]; then
  # SQL Server extension path - updated for Guacamole 1.x directory structure
  SQLSERVER_EXT_SRC="$EXT_STORE/extensions/guacamole-auth-jdbc/sqlserver"
  SQLSERVER_JDBC_SRC="$EXT_STORE/drivers/mssql-jdbc.jar"

  if [ -f "$GUAC_EXT"/*sqlserver*.jar ]; then
    oldSqlServerFiles=( "$GUAC_EXT"/*sqlserver*.jar )
    newSqlServerFiles=( "$SQLSERVER_EXT_SRC"/*sqlserver*.jar )

    if diff ${oldSqlServerFiles[0]} ${newSqlServerFiles[0]} >/dev/null ; then
    	echo "Using existing SQL Server extension."
      if [ ! -d /config/sqlserver-schema ]; then
        mkdir /config/sqlserver-schema
        cp -R "$SQLSERVER_EXT_SRC"/schema/* /config/sqlserver-schema
        CHANGES=true
      fi
    else
    	echo "Upgrading SQL Server extension."
    	rm "$GUAC_EXT"/*sqlserver*.jar
    	cp "$SQLSERVER_EXT_SRC"/*sqlserver*.jar "$GUAC_EXT"
      cp "$SQLSERVER_JDBC_SRC" /config/guacamole/lib/mssql-jdbc.jar
      rm -R /config/sqlserver-schema/*
      cp -R "$SQLSERVER_EXT_SRC"/schema/* /config/sqlserver-schema
      CHANGES=true
    fi
  else
    echo "Copying SQL Server extension."
    mkdir -p "$GUAC_EXT" /config/guacamole/lib /config/sqlserver-schema
    cp "$SQLSERVER_EXT_SRC"/*sqlserver*.jar "$GUAC_EXT"
    cp "$SQLSERVER_JDBC_SRC" /config/guacamole/lib/mssql-jdbc.jar
    cp -R "$SQLSERVER_EXT_SRC"/schema/* /config/sqlserver-schema
    CHANGES=true
  fi
elif [ "$OPTSQLSERVER" = "N" ]; then
  if [ -f "$GUAC_EXT"/*sqlserver*.jar ]; then
    echo "Removing SQL Server extension."
    rm "$GUAC_EXT"/*sqlserver*.jar
    rm -f /config/guacamole/lib/mssql-jdbc.jar
    rm -R /config/sqlserver-schema
  fi
fi

OPTPOSTGRESQL=${OPT_POSTGRESQL:-N}
if [ "$OPTPOSTGRESQL" = "Y" ]; then
  # PostgreSQL extension path - updated for Guacamole 1.x directory structure
  PG_EXT_SRC="$EXT_STORE/extensions/guacamole-auth-jdbc/postgresql"
  PG_JDBC_SRC="$EXT_STORE/drivers/postgresql-jdbc.jar"

  if [ -f "$GUAC_EXT"/*jdbc-postgresql*.jar ]; then
    oldPgFiles=( "$GUAC_EXT"/*jdbc-postgresql*.jar )
    newPgFiles=( "$PG_EXT_SRC"/*jdbc-postgresql*.jar )

    if diff ${oldPgFiles[0]} ${newPgFiles[0]} >/dev/null ; then
      echo "Using existing PostgreSQL extension."
      if [ ! -d /config/postgresql-schema ]; then
        mkdir /config/postgresql-schema
        cp -R "$PG_EXT_SRC"/schema/* /config/postgresql-schema
        CHANGES=true
      fi
    else
      echo "Upgrading PostgreSQL extension."
      rm "$GUAC_EXT"/*jdbc-postgresql*.jar
      cd /config/guacamole/lib
      rm postgresql-jdbc.jar 2>/dev/null || true
      cp "$PG_EXT_SRC"/*jdbc-postgresql*.jar "$GUAC_EXT"
      cp "$PG_JDBC_SRC" /config/guacamole/lib/postgresql-jdbc.jar
      rm -R /config/postgresql-schema/*
      cp -R "$PG_EXT_SRC"/schema/* /config/postgresql-schema
      CHANGES=true
    fi
  else
    echo "Copying PostgreSQL extension."
    mkdir -p "$GUAC_EXT" /config/guacamole/lib /config/postgresql-schema
    cp "$PG_EXT_SRC"/*jdbc-postgresql*.jar "$GUAC_EXT"
    cp "$PG_JDBC_SRC" /config/guacamole/lib/postgresql-jdbc.jar
    cp -R "$PG_EXT_SRC"/schema/* /config/postgresql-schema
    CHANGES=true
  fi
elif [ "$OPTPOSTGRESQL" = "N" ]; then
  if [ -f "$GUAC_EXT"/*jdbc-postgresql*.jar ]; then
    echo "Removing PostgreSQL extension."
    rm "$GUAC_EXT"/*jdbc-postgresql*.jar
    cd /config/guacamole/lib
    rm postgresql-jdbc.jar 2>/dev/null || true
    rm -R /config/postgresql-schema
  fi
fi

OPTLDAP=${OPT_LDAP:-N}
if [ "$OPTLDAP" = "Y" ]; then
  # LDAP extension path - updated for Guacamole 1.x directory structure
  LDAP_EXT_SRC="$EXT_STORE/extensions/guacamole-auth-ldap"

  if [ -f "$GUAC_EXT"/*ldap*.jar ]; then
    oldLDAPFiles=( "$GUAC_EXT"/*ldap*.jar )
    newLDAPFiles=( "$LDAP_EXT_SRC"/*ldap*.jar )

    if diff ${oldLDAPFiles[0]} ${newLDAPFiles[0]} >/dev/null ; then
    	echo "Using existing LDAP extension."
    else
    	echo "Upgrading LDAP extension."
    	rm "$GUAC_EXT"/*ldap*.jar
    	rm -R /config/ldap-schema/*
    	cp "$LDAP_EXT_SRC"/*.ldif /config/ldap-schema 2>/dev/null || true
    	cp "$LDAP_EXT_SRC"/*ldap*.jar "$GUAC_EXT"
      CHANGES=true
    fi
  else
    echo "Copying LDAP extension."
    mkdir -p "$GUAC_EXT" /config/ldap-schema
    cp "$LDAP_EXT_SRC"/*.ldif /config/ldap-schema 2>/dev/null || true
    cp "$LDAP_EXT_SRC"/*ldap*.jar "$GUAC_EXT"
    CHANGES=true
  fi
elif [ "$OPTLDAP" = "N" ]; then
  if [ -f "$GUAC_EXT"/*ldap*.jar ]; then
    echo "Removing LDAP extension."
    rm "$GUAC_EXT"/*ldap*.jar
    rm -R /config/ldap-schema
  fi
fi

OPTDUO=${OPT_DUO:-N}
if [ "$OPTDUO" = "Y" ]; then
  # Duo extension path - updated for Guacamole 1.x directory structure
  DUO_EXT_SRC="$EXT_STORE/extensions/guacamole-auth-duo"

  if [ -f "$GUAC_EXT"/*duo*.jar ]; then
    oldDuoFiles=( "$GUAC_EXT"/*duo*.jar )
    newDuoFiles=( "$DUO_EXT_SRC"/*duo*.jar )

    if diff ${oldDuoFiles[0]} ${newDuoFiles[0]} >/dev/null ; then
      echo "Using existing Duo extension."
    else
      echo "Upgrading Duo extension."
      rm "$GUAC_EXT"/*duo*.jar
      cp "$DUO_EXT_SRC"/*duo*.jar "$GUAC_EXT"
      CHANGES=true
    fi
  else
    echo "Copying Duo extension."
    mkdir -p "$GUAC_EXT"
    cp "$DUO_EXT_SRC"/*duo*.jar "$GUAC_EXT"
    CHANGES=true
  fi
elif [ "$OPTDUO" = "N" ]; then
  if [ -f "$GUAC_EXT"/*duo*.jar ]; then
    echo "Removing Duo extension."
    rm "$GUAC_EXT"/*duo*.jar
  fi
fi

OPTCAS=${OPT_CAS:-N}
if [ "$OPTCAS" = "Y" ]; then
  # CAS extension path - updated for Guacamole 1.x directory structure
  CAS_EXT_SRC="$EXT_STORE/extensions/guacamole-auth-sso/cas"

  if [ -f "$GUAC_EXT"/*cas*.jar ]; then
    oldCasFiles=( "$GUAC_EXT"/*cas*.jar )
    newCasFiles=( "$CAS_EXT_SRC"/*cas*.jar )

    if diff ${oldCasFiles[0]} ${newCasFiles[0]} >/dev/null ; then
      echo "Using existing CAS extension."
    else
      echo "Upgrading CAS extension."
      rm "$GUAC_EXT"/*cas*.jar
      cp "$CAS_EXT_SRC"/*cas*.jar "$GUAC_EXT"
      CHANGES=true
    fi
  else
    echo "Copying CAS extension."
    mkdir -p "$GUAC_EXT"
    cp "$CAS_EXT_SRC"/*cas*.jar "$GUAC_EXT"
    CHANGES=true
  fi
elif [ "$OPTCAS" = "N" ]; then
  if [ -f "$GUAC_EXT"/*cas*.jar ]; then
    echo "Removing CAS extension."
    rm "$GUAC_EXT"/*cas*.jar
  fi
fi

OPTOPENID=${OPT_OPENID:-N}
if [ "$OPTOPENID" = "Y" ]; then
  # OpenID extension path - updated for Guacamole 1.x directory structure
  OPENID_EXT_SRC="$EXT_STORE/extensions/guacamole-auth-sso/openid"

  if [ -f "$GUAC_EXT"/*openid*.jar ]; then
    oldOpenidFiles=( "$GUAC_EXT"/*openid*.jar )
    newOpenidFiles=( "$OPENID_EXT_SRC"/*openid*.jar )

    if diff ${oldOpenidFiles[0]} ${newOpenidFiles[0]} >/dev/null ; then
      echo "Using existing OpenID extension."
    else
      echo "Upgrading OpenID extension."
      rm "$GUAC_EXT"/*openid*.jar
      for jar in "$OPENID_EXT_SRC"/*.jar; do
        cp "$jar" "${GUAC_EXT}/1-$(basename "$jar")"
      done
      CHANGES=true
    fi
  else
    echo "Copying OpenID extension."
    mkdir -p "$GUAC_EXT"
    for jar in "$OPENID_EXT_SRC"/*.jar; do
      cp "$jar" "${GUAC_EXT}/1-$(basename "$jar")"
    done
    CHANGES=true
  fi
elif [ "$OPTOPENID" = "N" ]; then
  if [ -f "$GUAC_EXT"/*openid*.jar ]; then
    echo "Removing OpenID extension."
    rm "$GUAC_EXT"/*openid*.jar
  fi
fi

OPTTOTP=${OPT_TOTP:-N}
if [ "$OPTTOTP" = "Y" ]; then
  # TOTP extension path - updated for Guacamole 1.x directory structure
  TOTP_EXT_SRC="$EXT_STORE/extensions/guacamole-auth-totp"

  if [ -f "$GUAC_EXT"/*totp*.jar ]; then
    oldTotpFiles=( "$GUAC_EXT"/*totp*.jar )
    newTotpFiles=( "$TOTP_EXT_SRC"/*totp*.jar )

    if diff ${oldTotpFiles[0]} ${newTotpFiles[0]} >/dev/null ; then
      echo "Using existing TOTP extension."
    else
      echo "Upgrading TOTP extension."
      rm "$GUAC_EXT"/*totp*.jar
      cp "$TOTP_EXT_SRC"/*totp*.jar "$GUAC_EXT"
      CHANGES=true
    fi
  else
    echo "Copying TOTP extension."
    mkdir -p "$GUAC_EXT"
    cp "$TOTP_EXT_SRC"/*totp*.jar "$GUAC_EXT"
    CHANGES=true
  fi
elif [ "$OPTTOTP" = "N" ]; then
  if [ -f "$GUAC_EXT"/*totp*.jar ]; then
    echo "Removing TOTP extension."
    rm "$GUAC_EXT"/*totp*.jar
  fi
fi

OPTQUICKCONNECT=${OPT_QUICKCONNECT:-N}
if [ "$OPTQUICKCONNECT" = "Y" ]; then
  # Quick Connect extension path - updated for Guacamole 1.x directory structure
  QC_EXT_SRC="$EXT_STORE/extensions/guacamole-auth-quickconnect"

  if [ -f "$GUAC_EXT"/*quickconnect*.jar ]; then
    oldQCFiles=( "$GUAC_EXT"/*quickconnect*.jar )
    newQCFiles=( "$QC_EXT_SRC"/*quickconnect*.jar )

    if diff ${oldQCFiles[0]} ${newQCFiles[0]} >/dev/null ; then
      echo "Using existing Quick Connect extension."
    else
      echo "Upgrading Quick Connect extension."
      rm "$GUAC_EXT"/*quickconnect*.jar
      cp "$QC_EXT_SRC"/*quickconnect*.jar "$GUAC_EXT"
      CHANGES=true
    fi
  else
    echo "Copying Quick Connect extension."
    mkdir -p "$GUAC_EXT"
    cp "$QC_EXT_SRC"/*quickconnect*.jar "$GUAC_EXT"
    CHANGES=true
  fi
elif [ "$OPTQUICKCONNECT" = "N" ]; then
  if [ -f "$GUAC_EXT"/*quickconnect*.jar ]; then
    echo "Removing Quick Connect extension."
    rm "$GUAC_EXT"/*quickconnect*.jar
  fi
fi

OPTHEADER=${OPT_HEADER:-N}
if [ "$OPTHEADER" = "Y" ]; then
  # Header extension path - updated for Guacamole 1.x directory structure
  HEADER_EXT_SRC="$EXT_STORE/extensions/guacamole-auth-header"

  if [ -f "$GUAC_EXT"/*header*.jar ]; then
    oldQCFiles=( "$GUAC_EXT"/*header*.jar )
    newQCFiles=( "$HEADER_EXT_SRC"/*header*.jar )

    if diff ${oldQCFiles[0]} ${newQCFiles[0]} >/dev/null ; then
      echo "Using existing Header extension."
    else
      echo "Upgrading Header extension."
      rm "$GUAC_EXT"/*header*.jar
      cp "$HEADER_EXT_SRC"/*header*.jar "$GUAC_EXT"
      CHANGES=true
    fi
  else
    echo "Copying Header extension."
    mkdir -p "$GUAC_EXT"
    cp "$HEADER_EXT_SRC"/*header*.jar "$GUAC_EXT"
    CHANGES=true
  fi
elif [ "$OPTHEADER" = "N" ]; then
  if [ -f "$GUAC_EXT"/*header*.jar ]; then
    echo "Removing Header extension."
    rm "$GUAC_EXT"/*header*.jar
  fi
fi

OPTSAML=${OPT_SAML:-N}
if [ "$OPTSAML" = "Y" ]; then
  # SAML extension path - updated for Guacamole 1.x directory structure
  SAML_EXT_SRC="$EXT_STORE/extensions/guacamole-auth-sso/saml"

  if [ -f "$GUAC_EXT"/*saml*.jar ]; then
    oldQCFiles=( "$GUAC_EXT"/*saml*.jar )
    newQCFiles=( "$SAML_EXT_SRC"/*saml*.jar )

    if diff ${oldQCFiles[0]} ${newQCFiles[0]} >/dev/null ; then
      echo "Using existing SAML extension."
    else
      echo "Upgrading SAML extension."
      rm "$GUAC_EXT"/*saml*.jar
      cp "$SAML_EXT_SRC"/*saml*.jar "$GUAC_EXT"
      CHANGES=true
    fi
  else
    echo "Copying SAML extension."
    mkdir -p "$GUAC_EXT"
    cp "$SAML_EXT_SRC"/*saml*.jar "$GUAC_EXT"
    CHANGES=true
  fi
elif [ "$OPTSAML" = "N" ]; then
  if [ -f "$GUAC_EXT"/*saml*.jar ]; then
    echo "Removing SAML extension."
    rm "$GUAC_EXT"/*saml*.jar
  fi
fi

# SSL Auth extension (optional)
if [ ! -f "$GUAC_EXT"/guacamole-auth-sso-ssl.jar ] && [ -f "$EXT_STORE/extensions/guacamole-auth-sso/ssl/guacamole-auth-sso-ssl.jar" ]; then
  echo "Copying SSL Auth extension."
  mkdir -p "$GUAC_EXT"
  cp "$EXT_STORE/extensions/guacamole-auth-sso/ssl/guacamole-auth-sso-ssl.jar" "$GUAC_EXT/"
  CHANGES=true
fi

# Recording Storage extension (optional)
if [ ! -f "$GUAC_EXT"/guacamole-history-recording-storage.jar ] && [ -f "$EXT_STORE/extensions/guacamole-history-recording-storage/guacamole-history-recording-storage.jar" ]; then
  echo "Copying Recording Storage extension."
  mkdir -p "$GUAC_EXT"
  cp "$EXT_STORE/extensions/guacamole-history-recording-storage/guacamole-history-recording-storage.jar" "$GUAC_EXT/"
  CHANGES=true
fi

# Display Statistics extension (optional)
if [ ! -f "$GUAC_EXT"/guacamole-display-statistics.jar ] && [ -f "$EXT_STORE/extensions/guacamole-display-statistics/guacamole-display-statistics.jar" ]; then
  echo "Copying Display Statistics extension."
  mkdir -p "$GUAC_EXT"
  cp "$EXT_STORE/extensions/guacamole-display-statistics/guacamole-display-statistics.jar" "$GUAC_EXT/"
  CHANGES=true
fi

# KSM Vault extension (optional)
if [ ! -f "$GUAC_EXT"/guacamole-vault-ksm.jar ] && [ -f "$EXT_STORE/extensions/guacamole-vault/ksm/guacamole-vault-ksm.jar" ]; then
  echo "Copying KSM Vault extension."
  mkdir -p "$GUAC_EXT"
  cp "$EXT_STORE/extensions/guacamole-vault/ksm/guacamole-vault-ksm.jar" "$GUAC_EXT/"
  CHANGES=true
fi

# JSON Auth extension (optional)
if [ ! -f "$GUAC_EXT"/guacamole-auth-json.jar ] && [ -f "$EXT_STORE/extensions/guacamole-auth-json/guacamole-auth-json.jar" ]; then
  echo "Copying JSON Auth extension."
  mkdir -p "$GUAC_EXT"
  cp "$EXT_STORE/extensions/guacamole-auth-json/guacamole-auth-json.jar" "$GUAC_EXT/"
  CHANGES=true
fi

# Ban module (optional)
if [ ! -f "$GUAC_EXT"/guacamole-auth-ban.jar ] && [ -f "$EXT_STORE/extensions/guacamole-auth-ban/guacamole-auth-ban.jar" ]; then
  echo "Copying Ban module."
  mkdir -p "$GUAC_EXT"
  cp "$EXT_STORE/extensions/guacamole-auth-ban/guacamole-auth-ban.jar" "$GUAC_EXT/"
  CHANGES=true
fi

# Restrict module (optional)
if [ ! -f "$GUAC_EXT"/guacamole-auth-restrict.jar ] && [ -f "$EXT_STORE/extensions/guacamole-auth-restrict/guacamole-auth-restrict.jar" ]; then
  echo "Copying Restrict module."
  mkdir -p "$GUAC_EXT"
  cp "$EXT_STORE/extensions/guacamole-auth-restrict/guacamole-auth-restrict.jar" "$GUAC_EXT/"
  CHANGES=true
fi

if [ "$CHANGES" = true ]; then
  echo "Updating user permissions."
  chown abc:abc -R /config/guacamole
  chmod 755 -R /config/guacamole
else
  echo "No permissions changes needed."
fi

if [ "$OPTMYSQL" = "Y" ] && [ -f /etc/firstrun/mariadb.sh ]; then
  /etc/firstrun/mariadb.sh
  exec /sbin/tini -s -- /usr/bin/supervisord -n -c /etc/supervisor/conf.d/supervisord-mariadb.conf
else
  exec /sbin/tini -s -- /usr/bin/supervisord -n -c /etc/supervisor/conf.d/supervisord.conf
fi
