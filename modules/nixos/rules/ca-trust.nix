{ config, lib, pkgs, ... }:
let
  # Same CAs as /etc/ssl, minus security.pki.caCertificateBlacklist: in the
  # no-trust-rules bundle a blacklisted CA is just a name, with no PEM.
  bundle = "${builtins.dirOf config.security.pki.caBundle}/ca-no-trust-rules-bundle.crt";

  # The JDK ships its own cacerts keystore (OpenJDK's list, which still
  # trusts emSign, including roots NSS never had). Rebuild one from the
  # system bundle instead.
  javaTrustStore = pkgs.runCommand "nexos-java-cacerts" {
    nativeBuildInputs = [ pkgs.jdk_headless ];
  } ''
    mkdir certs
    awk '/-----BEGIN CERTIFICATE-----/ { n++; f = sprintf("certs/%03d.pem", n) }
         f { print > f }
         /-----END CERTIFICATE-----/ { f = "" }' ${bundle}
    for c in certs/*.pem; do
      keytool -importcert -noprompt -storetype PKCS12 -keystore $out \
        -storepass changeit -alias "$(basename $c .pem)" -file $c
    done
  '';
in
{
  environment.variables = {
    # nixpkgs' certifi (requests, pip, httpx...) uses its own copy of the
    # Mozilla bundle unless NIX_SSL_CERT_FILE is set; plain OpenSSL users
    # read SSL_CERT_FILE.
    NIX_SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
    SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";

    # Any JDK, from any nixpkgs (devShells, IDEs, Gradle). The JVM prints
    # "Picked up JAVA_TOOL_OPTIONS" on stderr because of this.
    JAVA_TOOL_OPTIONS = lib.concatStringsSep " " [
      "-Djavax.net.ssl.trustStore=${javaTrustStore}"
      "-Djavax.net.ssl.trustStoreType=PKCS12"
      "-Djavax.net.ssl.trustStorePassword=changeit"
    ];
  };
}
