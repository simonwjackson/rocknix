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

  environment.etc."ssh/authorized_keys.d/root".text = "";
  users.mutableUsers = true;
  users.users.root.hashedPassword = "!";
}
