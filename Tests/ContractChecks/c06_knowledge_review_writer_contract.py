#!/usr/bin/env python3
"""Source contract for the NPC knowledge-review writer.

Swift XCTest is NOT_RUN. HTTP is NOT_RUN. These counts are not HTTP.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = "2d4345987e1f84f913c3e64d12e575aa66533723"
COUNT = 0


def check(condition: bool, message: str) -> None:
    global COUNT
    if not condition:
        raise SystemExit(message)
    COUNT += 1


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def between(source: str, start: str, end: str) -> str:
    return source[source.index(start):source.index(end)]


def check_layout() -> None:
    diff = subprocess.run(
        ["git", "diff", "--name-only", BASE],
        cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False,
    )
    check(diff.returncode == 0, diff.stderr)
    changed = sorted(line for line in diff.stdout.splitlines() if line)
    check(changed == [
        "Core/MerchantNPCKnowledgeReviewWriter.swift",
        "Tests/ContractChecks/c06_knowledge_review_writer_contract.py",
        "docs/issue5-hunks/C06-knowledge-review-writer.hunk",
    ], "writer branch changed an unexpected file: " + ",".join(changed))
    untouched = subprocess.run(
        ["git", "diff", "--exit-code", BASE, "--",
         "Core/MerchantNPCOriginalDraftWriter.swift",
         "Core/MerchantNPCThemeDraftRequestRead.swift",
         "Tests/CoreTests/MerchantNPCOriginalDraftWriterTests.swift",
         "Tests/CoreTests/MerchantNPCThemeDraftRequestReadTests.swift",
         "App/AppSession.swift",
         "App/AppCompositionRoot.swift",
         "Questify.xcodeproj/project.pbxproj"],
        cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False,
    )
    check(untouched.returncode == 0, "theme-draft writer, session, or project changed\n" + untouched.stdout)


def check_writer() -> None:
    writer = read("Core/MerchantNPCKnowledgeReviewWriter.swift")
    submit = between(writer, "func submitForOriginalReview", "func publishApproved")
    publish = between(writer, "func publishApproved", "func makeSubmission")
    body = between(writer, "func makeSubmission", "func makeRequest")
    request = between(writer, "func makeRequest", "func makeReadRequest")
    read_request = between(writer, "func makeReadRequest", "func matches")
    match = between(writer, "func matches", "func recovered")
    recovered = between(writer, "func recovered", "func exactMember")
    check("class MerchantNPCKnowledgeReviewWriter: MerchantNPCOriginalReviewPublishing" in writer,
          "writer does not implement the review protocol")
    check('public static let path = "api/merchant/npc/knowledge-review"' in writer, "POST path is not the written contract")
    check("contract being written, not a route discovered" in writer, "path is described as a discovered route")
    check(writer.count("transport.send") == 2, "writer does not send the POST and then the GET")
    check(submit.count("transport.send") == 2 and "transport" not in publish, "publish sends a request")
    check(submit.index("transport.send") < submit.index("matches("), "GET is sent before the POST is accepted")
    rest = submit[submit.index("matches("):]
    check(rest.index("transport.send") < rest.index("recovered("), "the read is parsed before it is sent")
    check(submit.index("recovered(") < submit.index("return MerchantNPCOriginalReviewTicket"), "a ticket is returned before the read")
    check("MerchantNPCOriginalReviewTicket(requestID: requestID, scope: scope" in submit, "ticket does not keep the caller request id")
    check("knowledgeReviewAuthority" in submit, "mismatch does not throw the review waitingSource")
    check("knowledgeDraftHTTP" in publish and "waitingSource" in publish, "publishApproved does not throw the draft waitingSource")
    check("MerchantNpcKnowledgeDraftService.http" in writer, "publish capability is not the existing http source")
    check('httpMethod = "POST"' in request and request.count('httpMethod = "POST"') == 1, "submit is not the one POST")
    check('httpMethod = "GET"' not in request, "the POST request is a GET")
    check('httpMethod = "GET"' in read_request and read_request.count('httpMethod = "GET"') == 1, "the read is not the one GET")
    check('httpMethod = "POST"' not in read_request, "the read request is a POST")
    check('setValue(token, forHTTPHeaderField: "Authorization")' in request, "member token is not the Authorization header")
    check('setValue(token, forHTTPHeaderField: "Authorization")' in read_request, "read token is not the Authorization header")
    check('components.scheme == "https"' in request and 'components.scheme == "https"' in read_request, "writer does not hold the https configuration")
    check("url.query == nil" in request and "!url.absoluteString.contains(token)" in request, "token can be placed in the POST URL")
    check("!url.absoluteString.contains(token)" in read_request, "token can be placed in the GET URL")
    check('public static let readPath = "api/merchant/npc/knowledge-review/request"' in writer, "GET path is not the written contract")
    check('URLQueryItem(name: "requestId", value: requestID.uuidString)' in read_request, "GET query is not the same request id")
    check('"requestId": requestID.uuidString' in body, "body does not send the given request id")
    for key in ('"name": name', '"greeting": greeting', '"persona": persona', '"knowledge": knowledge'):
        check(key in body, "body is missing a draft field: " + key)
    check('Self.field(draft, "name")' in body and 'Self.field(draft, "knowledge")' in body, "fields are not taken from the draft")
    check('data["requestId"]' in match and "returned == requestID" in match, "a different POST requestId can become a ticket")
    check('exactMember(data["memberId"])' in match and "member == memberID" in match, "a different POST member can become a ticket")
    check('data["requestId"]' in recovered and "returned == requestID" in recovered, "a different GET requestId can be recovered")
    check('exactMember(data["memberId"])' in recovered and "member == memberID" in recovered, "a different GET member can be recovered")
    for key in ('data["name"] as? String == name', 'data["greeting"] as? String == greeting',
                'data["persona"] as? String == persona', 'data["knowledge"] as? String == knowledge'):
        check(key in recovered, "GET does not recover a posted field: " + key)
    check("Any other body is not a recovery." in writer, "any other body can be recovered")
    check("does not fall back to the submitted id" in writer, "missing response id can fall back to the submitted id")
    check("does not mint" in writer and "A nil approval is not published." in writer, "nil approval can publish")
    check("does not call `POST api/ai/theme/draft`" in writer, "writer does not name the theme-draft contract it refuses")
    check("does not wrap `MerchantNPCOriginalDraftWriter`" in writer, "writer does not name the theme-draft writer it refuses")
    code = "\n".join((submit, publish, body, request, read_request, match, recovered))
    for banned in (
        "UUID()", "Bearer ", "productType", "existingNodeNames",
        "api/ai/theme/draft", "api/merchant/npc/save", "createDraft", "generate(",
        "MerchantNPCOriginalDraftWriter", "MerchantNPCThemeDraftRequestRead",
        "traceId", "SAVED",
    ):
        check(banned not in code, "writer uses another contract: " + banned)
    check("knowledge-review/request" not in request, "POST uses the read path")
    check('httpMethod = "GET"' not in publish, "publish sends a GET")
    check("transport.send" not in publish, "publish sends a request")
    check(writer.count("func publishApproved") == 1, "publishApproved is missing")
    check("publishApproved(" not in submit, "submit calls publish")


def check_hunk_and_session() -> None:
    hunk = read("docs/issue5-hunks/C06-knowledge-review-writer.hunk")
    session = read("App/AppSession.swift")
    root = read("App/AppCompositionRoot.swift")
    project = read("Questify.xcodeproj/project.pbxproj")
    page = read("App/MerchantOperationsEditor.swift")
    for token in (
        "Not applied", "Do not apply", "Not inserted", "publisher: writer",
        "publisher stays nil", "App/AppSession.swift", "App/AppCompositionRoot.swift",
        "Questify.xcodeproj/project.pbxproj", "MerchantNPCKnowledgeReviewWriter(",
        "runtimeHTTPTransport", "api/merchant/npc/knowledge-review",
        "GET api/merchant/npc/knowledge-review/request?requestId=",
        "MerchantNpcKnowledgeDraftService.http", "does not send a publish request",
        "does not mint a second id", "MerchantOperationsDocumentView",
        "authorFlow: flow", "not added to the Xcode project", "HTTP is NOT_RUN", "NOT_RUN",
        "contract being written, not a route discovered",
        "does not call `POST api/ai/theme/draft`",
        "does not call\n`POST api/merchant/npc/save`",
        "generate/createDraft", "does not wrap `MerchantNPCOriginalDraftWriter`",
    ):
        check(token in hunk, "hunk is missing the unapplied attach: " + token)
    check("MerchantNPCKnowledgeReviewWriter" not in session, "AppSession constructs the writer")
    check("publisher: writer" not in session, "AppSession no longer keeps publisher nil")
    check("MerchantNPCKnowledgeReviewWriter" not in root, "composition root constructs the writer")
    check("MerchantNPCKnowledgeReviewWriter.swift" not in project, "project file gained the writer")
    check("MerchantNPCKnowledgeReviewWriter" not in page, "character page calls the writer directly")
    check("NOT_RUN" in Path(__file__).read_text(encoding="utf-8"), "contract claims swift or HTTP ran")


def main() -> None:
    check_layout()
    check_writer()
    check_hunk_and_session()
    sys.stdout.write(str(COUNT) + "\n")


if __name__ == "__main__":
    main()
