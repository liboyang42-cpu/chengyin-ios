#!/usr/bin/env python3
"""Offline P122 wiring/source guard; never a Swift compile or iOS execution claim."""
import argparse
import hashlib
import json
import pathlib
import re
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASELINE = "34928c87f43a6b97bfc0b01f8bcc8dba0d9b1631"
ALLOWLIST = {
    "App/TicketWalletView.swift", "App/AccountView.swift",
    "App/TicketWalletPendingOrderNavigation.swift", "Resources/TicketPendingOrder.xcstrings",
    "Tests/AppUnitTests/TicketWalletPendingOrderNavigationTests.swift",
    "tools/check_ticket_pending_order_navigation.py",
}


def require(condition, message):
    if not condition:
        raise SystemExit("FAIL: " + message)


def native_check():
    nav = (ROOT / "App/TicketWalletPendingOrderNavigation.swift").read_text()
    wallet = (ROOT / "App/TicketWalletView.swift").read_text()
    account = (ROOT / "App/AccountView.swift").read_text()
    tests = (ROOT / "Tests/AppUnitTests/TicketWalletPendingOrderNavigationTests.swift").read_text()
    for token in [
        "static let defaultValue: TicketWalletPendingOrderProvider? = nil",
        "ticket.id > 0 && ticket.registrationStatus == 1", "owner.wallet.canRead",
        "ObjectIdentifier(coordinator)", "orderScope = coordinator.scope",
        "accountID = coordinator.accountID", "revision: currentRevision()",
        "target.owner == owner", "snapshot.tickets[rowIndex] == ticket",
        "snapshot.tickets[target.rowIndex] == target.ticket", "self.presentationID == presentationID",
        "visible && target == nil", "return OrderLifecycleView(id: target.ticket.id, coordinator: coordinator)",
    ]:
        require(token in nav, "navigation guard missing: " + token)
    for forbidden in ["OrderLifecycleCoordinator(", ".confirm(", ".prepare(", ".load(", "HTTPTransport", "URLSession", "Task {", "api/registration/"]:
        require(forbidden not in nav, "navigation seam may not create or dispatch: " + forbidden)
    for token in [
        "pendingOrderReadOwner == provider.owner", "model.accepts(offeredPresentation, currentOwner: key)",
        "let current = model.value(owner: key)", "rowIndex: rowIndex, snapshot: current",
        ".navigationDestination(item: $pendingOrderEntry.target)", "pendingOrderEntry.matches(target, snapshot: snapshot",
        "model.value(owner: captured) != nil", "captured == key", "provider.owner == pendingOrderProvider?.owner",
        "pendingOrderEntry.disappear()", "pendingOrderEntry.appear()", "retirePendingOrder()",
        'Text("ticketPendingOrder.open", tableName: "TicketPendingOrder")',
        "TicketWalletDetailView(id: ticket.id, reader: reader", "showsActionNotice: true",
    ]:
        require(token in wallet, "wallet wiring missing: " + token)
    require(account.count(".environment(\\.ticketWalletPendingOrderProvider, ticketPendingOrderProvider)") == 1,
            "provider must be mounted exactly once in Account wallet sheet")
    require("TicketWalletPendingOrderProvider(reader: session.ticketWalletReader, coordinator: session.orderLifecycleCoordinator," in account,
            "Account must retain its existing coordinator")
    require("revision: session.sessionRevision, currentRevision: { session.sessionRevision }" in account, "session revision guard missing")
    catalog = json.loads((ROOT / "Resources/TicketPendingOrder.xcstrings").read_text())
    require(catalog["sourceLanguage"] == "en", "catalog source language")
    require(set(catalog["strings"]) == {"ticketPendingOrder.open"}, "catalog scope")
    strings = catalog["strings"]["ticketPendingOrder.open"]["localizations"]
    require(set(strings) == {"en", "zh-Hans"}, "catalog languages")
    for language, value in [("en", "View pending order"), ("zh-Hans", "查看待支付订单")]:
        require(strings[language]["stringUnit"] == {"state": "translated", "value": value}, "honest destination label")
    names = re.findall(r"func (test\w+)\(", tests)
    require(len(names) == 18 and len(set(names)) == 18, "expected 18 distinct authored app-unit tests")
    print("PASS native structural guards and isolated bilingual catalog")
    print("AUTHORED 18 app-unit XCTest methods; NOT_RUN Apple compilation/XCTest/UI execution")


def boundary_check():
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    require(head == BASELINE, "this strict candidate-boundary check requires the recorded baseline")
    changed = set(subprocess.check_output(["git", "diff", "--name-only", "HEAD"], cwd=ROOT, text=True).splitlines())
    changed.update(subprocess.check_output(["git", "ls-files", "--others", "--exclude-standard"], cwd=ROOT, text=True).splitlines())
    require(changed == ALLOWLIST, "candidate must match exact six-path allowlist: " + repr(sorted(changed)))
    subprocess.run(["git", "diff", "--check"], cwd=ROOT, check=True)
    print("PASS exact baseline, six-path boundary, and git diff --check; AppSession/PBX/shared locale/payment locks unchanged")


def mini_check(path):
    data = json.loads(path.read_text())
    ref = "4f230354795772a35d71245578188ac1b31374d1"
    require(data["fixed_ref"] == ref and data["repository"] == "liboyang42-cpu/chengyin", "Mini fixed identity")
    for key, filename, sha in [("js", "index.js", "72719da8a433d92254cb2adba6f9e0e2d25af5cb"),
                               ("wxml", "index.wxml", "000d4bcac227ccbf6905774a22a53dea5b16f388")]:
        item = data[key]; raw = item["content"].encode()
        require(item["encoding"] == "utf-8", "Mini encoding")
        require(hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest() == sha == item["sha"], "Mini blob hash " + key)
        require(item["display_url"] == f"https://github.com/liboyang42-cpu/chengyin/blob/{ref}/chengyinhub-xcx/subpackageMember/signup/{filename}", "Mini source URL")
    require('bindtap="goTicket"' in data["wxml"]["content"], "Mini card event")
    require(shutil.which("node") is not None, "Node required for actual Mini event execution")
    js = r'''
const fs = require('fs'), vm = require('vm'), assert = require('assert/strict');
const evidence = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
let page, routes = [], notices = [], cases = 0;
vm.runInNewContext(evidence.js.content, {
  Page: p => page = p, getApp: () => ({ globalData: {}, getImgUrl: x => x }),
  require: () => m => notices.push(m), wx: { navigateTo: v => routes.push(v.url) }
});
for (const kind of ['topic', 'activity']) {
  for (const status of [undefined, -1, 0, 1, 2, 3, 4, 99]) {
    for (const verificationStatus of [0, 1]) {
      routes = []; notices = [];
      const item = {id: 41, registrationStatus: status, verificationStatus, ownerId: 900, kind};
      page.data.ticketList = [item];
      page.goTicket.call(page, {currentTarget: {dataset: {index: 0}}});
      if (status === 1) assert.deepEqual(routes, ['/subpackageMember/orderinfo/orderinfo?id=41']);
      else {
        assert(!routes.some(x => x.includes('/orderinfo/')));
        if (status === 2) assert(routes[0].startsWith('/pages/play/index?'));
        else assert.equal(routes.length, 0);
      }
      cases++;
    }
  }
}
for (const id of [undefined, 0]) {
  routes = []; page._openTicket({id, registrationStatus: 1}, 'topic'); assert.equal(routes.length, 0); cases++;
}
console.log(`PASS ${cases} actual Mini goTicket/_openTicket cases; pending registration ID preserved, other statuses never route to order`);
'''
    subprocess.run(["node", "-e", js, str(path.resolve())], check=True)
    print("PASS fixed Mini git-blob hashes; evidence SHA256 " + hashlib.sha256(path.read_bytes()).hexdigest())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mini-evidence", type=pathlib.Path)
    parser.add_argument("--strict-candidate-boundary", action="store_true")
    args = parser.parse_args()
    native_check()
    if args.strict_candidate_boundary:
        boundary_check()
    if args.mini_evidence:
        mini_check(args.mini_evidence)
    else:
        print("NOT_RUN Mini source execution: pass --mini-evidence with the fixed local source receipt")
