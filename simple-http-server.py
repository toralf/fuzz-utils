#!/usr/bin/env python
# SPDX-License-Identifier: GPL-3.0-or-later
# -*- coding: utf-8 -*-

import argparse
import logging
import re
import socket
from http.server import HTTPServer, SimpleHTTPRequestHandler


class HTTPServerV6(HTTPServer):
    address_family = socket.AF_INET6


class MyHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        try:
            logging.debug(self.requestline)
            return SimpleHTTPRequestHandler.do_GET(self)
        except BrokenPipeError:
            logging.info("pipe broken")
        except Exception as e:
            logging.exception("MyHandler: {}".format(e), exc_info=False)


def main():
    logging.basicConfig(
        format="%(asctime)s %(name)s %(levelname)s + %(message)s", level=logging.INFO
    )
    logging.debug("Parsing args...")
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--address", type=str, help="default: localhost", default="localhost"
    )
    parser.add_argument("--port", type=int, help="default: 1234", default=1234)
    parser.add_argument(
        "--is_ipv6", type=bool, help="mark ADDRESS as IPv6", default=False
    )
    args = parser.parse_args()

    if args.is_ipv6 or re.match(":", args.address):
        address = str(args.address).replace("[", "").replace("]", "")
        server = HTTPServerV6((address, args.port), MyHandler)
    else:
        server = HTTPServer((args.address, args.port), MyHandler)

    logging.info("running at %s at %s", args.address, args.port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logging.info("catched Ctrl-C")
    except Exception as e:
        logging.exception("main: {}".format(e), exc_info=False)


if __name__ == "__main__":
    main()
