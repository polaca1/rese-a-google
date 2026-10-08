import importlib.util
from pathlib import Path


def actions():
    spec = importlib.util.spec_from_file_location('linux_actions', Path(__file__).parents[1] / 'linux/action.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_address_only_after_background_funnel_is_public_and_targets_account_service():
    module = actions()
    host = 'reviewnfcgo.example.ts.net'
    state = {'BackendState': 'Running', 'Self': {'DNSName': host + '.'}}
    funnel = {'AllowFunnel': {host + ':443': True}, 'Web': {host + ':443': {'Handlers': {'/': {'Proxy': 'http://127.0.0.1:8080'}}}}}
    assert module.public_origin(state, funnel) == 'https://' + host
    assert module.public_origin(state, {}) is None
    funnel['AllowFunnel'][host + ':443'] = False
    assert module.public_origin(state, funnel) is None
    funnel['AllowFunnel'][host + ':443'] = True
    funnel['Web'][host + ':443']['Handlers']['/']['Proxy'] = 'http://127.0.0.1:9999'
    assert module.public_origin(state, funnel) is None


def test_not_connected_and_untrusted_addresses_never_become_public_endpoint():
    module = actions()
    for name in ('https://example.com', 'localhost', 'server.ts.net/evil', 'server.ts.net:443', 'server.example.com'):
        assert module.public_origin({'BackendState': 'Running', 'Self': {'DNSName': name}}, {}) is None
    assert module.public_origin({'BackendState': 'NeedsLogin', 'Self': {'DNSName': 'pc.example.ts.net'}}, {}) is None
