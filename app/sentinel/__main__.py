"""Entry points.

    python -m sentinel ask "What is the return window?"   answer one question
    python -m sentinel orders-api                         run the mock orders API
"""

import sys


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if argv[:1] == ["orders-api"]:
        from .orders_api import serve
        serve()
        return 0
    if argv[:1] == ["ask"] and len(argv) == 2:
        import boto3

        from .agent import ask
        from .model import Ollama
        from .tools import from_env

        print(ask(argv[1], Ollama(), from_env(boto3.client("s3"))))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
