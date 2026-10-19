#!/usr/bin/env python3
"""A second person in a room, on a second node: for demos and recordings.

Invites node B into node A's room (namespace invite -> join -> group sync ->
context join), joins the room as `--name`, gets editor from A, then walks a
viewpoint around and places a few objects, so whoever has the room open on A
sees another member arrive and build, live, over peer-to-peer sync.

    scripts/demo-peer.py --a http://localhost:4301 --b http://localhost:4311 \\
        --context <room id> [--name Leo] [--delay 6]

Both nodes use the dev admin login (admin / calimero1234, override with
--user / --password). Standard library only.
"""

import argparse
import json
import math
import sys
import time
import urllib.error
import urllib.request
import uuid


class Node:
    def __init__(self, url, user, password):
        self.url = url.rstrip("/")
        self.token = self.request("POST", "/auth/token", {
            "auth_method": "user_password", "public_key": user, "client_name": "demo-peer",
            "permissions": ["admin"], "timestamp": int(time.time()),
            "provider_data": {"username": user, "password": password},
        }, auth=False)["data"]["access_token"]

    def request(self, method, path, body=None, auth=True):
        headers = {"content-type": "application/json"}
        if auth:
            headers["authorization"] = "Bearer " + self.token
        req = urllib.request.Request(
            self.url + path, method=method, headers=headers,
            data=json.dumps(body).encode() if body is not None else None)
        try:
            with urllib.request.urlopen(req, timeout=70) as res:
                text = res.read().decode()
                return json.loads(text) if text else {}
        except urllib.error.HTTPError as err:
            raise SystemExit(f"{method} {path} -> HTTP {err.code}: {err.read().decode()[:300]}")

    def call(self, context, method, args=None):
        res = self.request("POST", "/jsonrpc", {
            "jsonrpc": "2.0", "id": 1, "method": "execute",
            "params": {"contextId": context, "method": method, "argsJson": args or {}},
        })
        if "error" in res:
            raise SystemExit(f"{method}: {json.dumps(res['error'])[:300]}")
        return res.get("result", {}).get("output")


def now_ms():
    return int(time.time() * 1000)


def place(node, context, kind, color, x, z, scale=1.0, content=None):
    data = {"kind": kind}
    if content:
        data["content"] = content
    node.call(context, "add_object", {"object": {
        "id": str(uuid.uuid4()), "data": data,
        "transform": {"position": {"x": x, "y": 0, "z": z}, "rotation": {"x": 0, "y": 0, "z": 0, "w": 1},
                      "scale": {"x": scale, "y": scale, "z": scale}},
        "color": color, "lockedBy": None, "createdBy": "", "createdAt": now_ms(), "updatedAt": now_ms(),
        "version": 0,
    }})


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--a", required=True, help="the room owner's node")
    ap.add_argument("--b", required=True, help="the second person's node")
    ap.add_argument("--context", required=True, help="the room (context) id")
    ap.add_argument("--name", default="Leo")
    ap.add_argument("--user", default="admin")
    ap.add_argument("--password", default="calimero1234")
    ap.add_argument("--delay", type=float, default=6, help="seconds before the second person starts building")
    args = ap.parse_args()

    a = Node(args.a, args.user, args.password)
    b = Node(args.b, args.user, args.password)

    room_group = a.request("GET", f"/admin-api/contexts/{args.context}/group")["data"]
    # A room sits in a subgroup; invitations go through its namespace.
    group = room_group
    for ns in a.request("GET", "/admin-api/namespaces")["data"]:
        nid = ns["namespaceId"]
        groups = a.request("GET", f"/admin-api/namespaces/{nid}/groups").get("data") or []
        if nid == room_group or any(g.get("groupId") == room_group for g in groups):
            group = nid
            break
    print("room namespace:", group)
    invitation = a.request("POST", f"/admin-api/namespaces/{group}/invite", {})["data"]
    invitation = invitation.get("invitation", invitation)
    for attempt in range(10):
        try:
            b.request("POST", f"/admin-api/namespaces/{group}/join", {"invitation": invitation})
            break
        except SystemExit as err:
            if "already" in str(err).lower():
                break
            if attempt == 9:
                raise
            time.sleep(2)
    b.request("POST", f"/admin-api/groups/{group}/sync", {})
    for _ in range(20):
        try:
            b.request("POST", f"/admin-api/contexts/{args.context}/join", {})
            break
        except SystemExit:
            time.sleep(2)
    print("node B is in the room")

    # B's copy of the room initialises once its state syncs from A.
    me = None
    for _ in range(60):
        try:
            me = b.call(args.context, "whoami")
            break
        except SystemExit:
            time.sleep(1)
    if not me:
        raise SystemExit("node B's copy of the room never initialised")
    b.call(args.context, "join", {"username": args.name, "avatar": None, "timestamp": now_ms()})
    a.call(args.context, "grant_editor", {"member": me})
    print(f"{args.name} joined as editor:", me)

    time.sleep(args.delay)
    builds = [
        ("sphere", "F472B6", 0.32, -0.18, 1.1), ("cube", "22D3EE", -0.4, -0.2, 0.9),
        ("arrow", "FBBF24", 0.0, -0.75, 1.3), ("marker", "34D399", 0.45, -0.6, 1.0),
    ]
    for step in range(28):
        t = step / 4
        b.call(args.context, "update_presence", {
            "camera_position": {"x": math.sin(t) * 0.9, "y": 1.2, "z": 0.3 + math.cos(t) * 0.4},
            "camera_rotation": {"x": 0, "y": 0, "z": 0, "w": 1}, "updated_at": now_ms(),
        })
        if step % 6 == 3 and builds:
            kind, color, x, z, scale = builds.pop(0)
            place(b, args.context, kind, color, x, z, scale)
            print(f"{args.name} placed a {kind}")
        time.sleep(0.6)


if __name__ == "__main__":
    sys.exit(main())
