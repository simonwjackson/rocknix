{ ... }:

{
  services.openssh = {
    enable = true;
    ports = [ 2222 ];
    authorizedKeysFiles = [ "/etc/ssh/authorized_keys.d/%u" ];
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  users.mutableUsers = true;
  users.users.root.hashedPassword = "!";
}
