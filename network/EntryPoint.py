from mininet.log import setLogLevel
import Shared as shared
import ApiManager as apiMgr
import NetworkManager as netMgr
import argparse
import threading
import time

if __name__ == '__main__':
    setLogLevel( 'info' )  # for CLI output
    parser = argparse.ArgumentParser(description="Mininet Network",
                                     formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument("-s", "--servers", help="Server hosts names. E.g: [h1]", required=False)
    parser.add_argument("-a", "--attackers", help="Attacker hosts names. E.g: [h1]", required=False)
    parser.add_argument("-uhb", "--unified-host-bandwidth", help="When used, all non-server hosts will have same passed bandwidth", required=False)
    parser.add_argument("-usb", "--unified-switch-bandwidth", help="When used, all controlled switches will have same passed bandwidth", required=False)
    parser.add_argument("-mr", "--manuel-receivers", action="store_true", help="Whether to start DITG receivers only on manual request")
    parser.add_argument("-ncs", "--nbr-controlled-switches", help="The number of controlled switches in the network", required=False)
    parser.add_argument("-htf", "--hosts-topo-file",
                        help="When given, the provided JSON file in the 'input-data' folder will be used. E.g: hosts-topology-6hosts",
                        required=False, default="hosts-toplogy-6hosts")

    config = vars(parser.parse_args())
    shared.init(config)
    apiMgr.run_flask(shared.GLOBALS)
    try:
        netMgr.run_mininet(shared.GLOBALS)
    except Exception as e:
        print(f"WARNING: Mininet initialization failed (likely needs root): {e}")
        print("NOTICE: Flask API server is still running on http://127.0.0.1:5000")
        print("INFO: Keeping process alive so API can still be accessed...")
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nShutting down...")
        pass