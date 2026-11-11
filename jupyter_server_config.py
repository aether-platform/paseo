import os
c = get_config()  # noqa
c.ServerApp.base_url = "/user/alice/"
c.ServerApp.port = 18888
c.ServerApp.ip = "127.0.0.1"
c.ServerApp.open_browser = False
c.IdentityProvider.token = ""
c.ServerApp.password = ""
c.ServerApp.disable_check_xsrf = True
ABS = os.environ.get("JSP_ABSOLUTE_URL") == "1"

def paseo_command(port, base_url):
    return [
        "env",
        f"PASEO_HOME=$SCRATCH/home-jsp",
        f"PASEO_LISTEN=127.0.0.1:{port}",
        "PASEO_WEB_UI_ENABLED=true",
        "PASEO_RELAY_ENABLED=false",
        "PASEO_HOSTNAMES=hub.example.test",
        f"PASEO_BASE_PATH={base_url}paseo",
        "/home/kaz/.nvm/versions/node/v22.23.4/bin/node",
        "/home/kaz/work/cc-paseo-basepath/paseo/packages/server/dist/scripts/supervisor-entrypoint.js",
    ]

c.ServerProxy.servers = {
    "paseo": {
        "command": paseo_command,
        "absolute_url": ABS,
        "timeout": 60,
        "launcher_entry": {"enabled": False},
    }
}
c.ServerApp.allow_remote_access = True
