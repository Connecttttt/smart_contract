from brownie import Bridge, BridgeToken, accounts


def deploy():
    acct = accounts.load("test-1")
    bridge = Bridge.deploy(BridgeToken[-1], {"from": acct})


def deploy_bridge_token():
    acct = accounts.load("test-1")
    bridge_token = BridgeToken.deploy({"from": acct})


def get_current_timestamp():
    time_stamp = Bridge[-1].getCurrentTimestamp()
    print(time_stamp)


def main():
    deploy()


# gobi-testnet
# bridge tokenn address = 0xEF53020fEb7b71E4B700531894991Cc7Ca553fb4
# bridge core address = 0xAC90cdbBb9AD436bDcF9693706dd900702105E55
