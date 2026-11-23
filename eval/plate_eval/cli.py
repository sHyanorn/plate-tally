"""Command line: python -m plate_eval <command>."""

import argparse
from collections.abc import Sequence

import anthropic

from plate_eval import config, runner, sampler, scorer


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="plate_eval")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("build-pool", help="download the dataset metadata and write the pool")
    sample = commands.add_parser("sample", help="draw the fixed random sample from the pool")
    sample.add_argument("--check", action="store_true", help="compare with the committed sample")
    run = commands.add_parser("run", help="call the models on the sample")
    run.add_argument("--dry-run", action="store_true", help="print the plan and cost, call nothing")
    run.add_argument("--ack-halt", action="store_true", help="delete HALTED.txt and continue")
    commands.add_parser("score", help="score the raw records")
    args = parser.parse_args(argv)

    if args.command == "build-pool":
        return sampler.cmd_build_pool()
    if args.command == "sample":
        return sampler.cmd_sample(args.check)
    if args.command == "score":
        return scorer.score()
    if args.dry_run:
        print(runner.dry_run_report())
        return 0
    client = anthropic.Anthropic(max_retries=0, timeout=config.TIMEOUT_S)
    return runner.run(client, ack_halt=args.ack_halt)
