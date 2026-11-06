#!/usr/bin/env python3
"""Synthetic loopback fixture: no real service, secrets, audio or device."""
import http.server, json, os, socket, subprocess, sys, threading, time
from pathlib import Path
class Server(http.server.ThreadingHTTPServer):
    daemon_threads=True
    requests=[]
    mode=""
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def do_POST(self):
        length=int(self.headers.get("Content-Length","0"))
        obj=json.loads(self.rfile.read(length))
        cmd=obj.get("command");args=obj.get("args",{})
        self.server.requests.append((cmd,args))
        # Synthetic transport faults, at discovery or after a queue action was
        # sent. Never dump request bytes, headers or credential data.
        fault=self.server.mode.removeprefix("main-")
        fault_stage=(cmd=="players/all" and fault in ("eof-discovery","stall-discovery")) or (cmd=="player_queues/pause" and fault in ("eof-command","truncated-command","server-error-command","stall-command"))
        if fault_stage:
            if fault.startswith("stall-"):
                time.sleep(9.5)
                return
            if fault=="server-error-command":
                self.send_response(503);self.end_headers();return
            if fault=="truncated-command":
                self.send_response(200);self.send_header("Content-Type","application/json");self.send_header("Content-Length","100");self.end_headers();self.wfile.write(b'{"res');self.wfile.flush()
            try:self.connection.shutdown(socket.SHUT_RDWR)
            except OSError:pass
            self.connection.close()
            return
        if (self.server.mode=="main-preempt-read-pause" and cmd=="player_queues/get") or (self.server.mode=="main-preempt-items-next" and cmd=="player_queues/items"):
            time.sleep(.5)
        response={"message_id":obj.get("message_id"),"result":None}
        if cmd=="players/all":
            if self.server.mode=="owner-change":time.sleep(.2)
            output={"output_protocol_id":"synthetic-client","protocol_domain":"sendspin","available":True,"derived_from":None}
            player={"player_id":"synthetic-wrapper","provider":"universal_player","type":"player","available":True,"enabled":True,"active_group":None,"synced_to":None,"group_members":[],"static_group_members":[],"active_output_protocol":None,"output_protocols":[output]}
            if self.server.mode=="grouped": player["active_group"]="synthetic-group"
            response["result"]=[player,dict(player,player_id="second-wrapper")] if self.server.mode=="ambiguous" else [player]
        elif cmd=="player_queues/get":
            response["result"]={"queue_id":"wrong-wrapper" if self.server.mode=="wrong-queue" else "synthetic-wrapper","state":"playing","active":True,"elapsed_time":13,"elapsed_time_last_updated":time.time(),"current_index":None,"index_in_buffer":None,"current_item":{"name":"Synthetic Track","queue_item_id":"current-id","duration":120},"next_item":{"name":"Synthetic Next","queue_item_id":"next-id"}}
            response["result"]["items"]="0" if self.server.mode=="bad-count-play" else (0 if self.server.mode=="empty-play" else 2)
            if self.server.mode=="empty-play":
                response["result"].update(current_item=None,next_item=None,state="idle",active=False)
        elif cmd=="player_queues/items":
            response["result"]=[{"queue_id":"wrong-wrapper" if self.server.mode=="items-wrong" else "synthetic-wrapper","name":"Synthetic Track","queue_item_id":"first-upcoming"},{"queue_id":"synthetic-wrapper","name":"Synthetic Next","queue_item_id":"second-upcoming"}]
            if self.server.mode=="items-too-many": response["result"]*=6
        elif self.server.mode=="denied":
            self.send_response(403);self.end_headers();return
        if cmd.startswith("player_queues/") and self.server.mode=="owner-after-send": time.sleep(.4)
        if cmd.startswith("player_queues/") and self.server.mode=="wrong-message": response["message_id"]="obsolete"
        if cmd.startswith("player_queues/") and self.server.mode in ("raw-pause","raw-play","raw-read","main-raw-pause","main-raw-read","items","raw-items","items-wrong","items-too-many","main-items","main-raw-items"): response=response["result"]
        data=json.dumps(response).encode();self.send_response(200);self.send_header("Content-Type","application/json");self.send_header("Content-Length",str(len(data)));self.end_headers()
        try:self.wfile.write(data)
        except (BrokenPipeError,ConnectionResetError):pass
def run(mode):
    server=Server(("127.0.0.1",0),Handler);server.requests=[];server.mode=mode
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    try:
        env=dict(os.environ,TVQ_MODE=mode,TVQ_URL="http://127.0.0.1:%d"%server.server_port)
        main=mode.startswith("main-")
        script="res://tests/test_ma_tv_queue_main.gd" if main else "res://tests/test_ma_tv_queue.gd"
        try:
            result=subprocess.run(["xvfb-run","-a",sys.argv[1],"--path",os.environ.get("SHIELDAMP_TEST_PROJECT",str(Path(__file__).resolve().parents[2]/"app")),"--audio-driver","Dummy","-s",script],env=env,text=True,capture_output=True,timeout=25)
        except subprocess.TimeoutExpired as e:
            print("synthetic timeout stdout",e.stdout,"stderr",e.stderr)
            raise
        assert result.returncode==0, (mode,result.stderr,result.stdout)
        assert "SCRIPT ERROR" not in result.stderr+result.stdout, (mode,result.stderr,result.stdout)
        success=mode in ("pause","play","resume-play","read","raw-pause","raw-play","raw-read","items","raw-items","bad-count-play")
        assert ("MAIN_QUEUE_OK=True" if main else ("FIXTURE_OK=True" if success else "FIXTURE_OK=False")) in result.stdout,(mode,result.stdout)
        if not main: assert "FIXTURE_CREDENTIAL_RELEASED=True" in result.stdout,(mode,result.stdout)
        expected={"resume-play":"player_queues/resume","empty-play":"player_queues/get","bad-count-play":"player_queues/play","pause":"player_queues/pause","play":"player_queues/play","read":"player_queues/get","denied":"player_queues/pause","main-pause":"player_queues/pause","main-play":"player_queues/play","main-read":"player_queues/get","main-items":"player_queues/items","main-raw-items":"player_queues/items","main-busy-items":"player_queues/items","main-busy-close":"player_queues/get","eof-command":"player_queues/pause","truncated-command":"player_queues/pause","server-error-command":"player_queues/pause","stall-command":"player_queues/pause","main-eof-command":"player_queues/pause","items":"player_queues/items","raw-items":"player_queues/items","items-wrong":"player_queues/items","items-too-many":"player_queues/items","raw-pause":"player_queues/pause","raw-play":"player_queues/play","raw-read":"player_queues/get","main-raw-pause":"player_queues/pause","main-raw-read":"player_queues/get","wrong-queue":"player_queues/get","wrong-message":"player_queues/pause","owner-after-send":"player_queues/pause"}.get(mode)
        commands=[x[0] for x in server.requests]
        wanted=["players/all", "player_queues/get", "players/all", "player_queues/items"] if mode=="main-busy-items" else (["players/all",expected] if expected else ["players/all"])
        if mode=="main-preempt-read-pause": wanted=["players/all","player_queues/get","players/all","player_queues/pause"]
        elif mode=="main-preempt-items-next": wanted=["players/all","player_queues/items","players/all","player_queues/next","players/all","player_queues/items"]
        elif mode=="main-busy-mutation": wanted=["players/all","player_queues/pause"]
        if expected in ["player_queues/play","player_queues/resume"]:wanted=["players/all","player_queues/get",expected]
        if expected=="player_queues/items" and mode!="main-busy-items":wanted=["players/all","player_queues/get",expected]
        if mode=="main-busy-items":wanted=["players/all","player_queues/get","players/all","player_queues/get","player_queues/items"]
        if mode=="main-preempt-items-next":wanted=["players/all","player_queues/get","player_queues/items","players/all","player_queues/next","players/all","player_queues/get","player_queues/items"]
        assert commands==wanted,(mode,commands)
        if mode.startswith("main-preempt-") or mode=="main-busy-mutation":
            mutations=[command for command in commands if command not in ["players/all","player_queues/get","player_queues/items"]]
            assert len(mutations)==1,(mode,mutations)
            assert all(args.get("queue_id")=="synthetic-wrapper" for command,args in server.requests if command.startswith("player_queues/")),mode
        if expected:
            expected_args={"queue_id":"synthetic-wrapper"}
            if expected=="player_queues/items": expected_args.update(limit=10,offset=0)
            assert server.requests[-1][1]==expected_args,mode
        if mode=="empty-play":assert "YOUR QUEUE IS EMPTY / CHOOSE MUSIC" in result.stdout and "player_queues/play" not in commands
        if mode=="read": assert "FIXTURE_CURRENT=Synthetic Track" in result.stdout
        if not main and mode in ("eof-discovery","stall-discovery","eof-command","truncated-command","server-error-command","stall-command"):
            expected_detail="MUSIC ASSISTANT CONNECTION FAILED" if mode.endswith("discovery") else "PLAYBACK COMMAND RESULT UNKNOWN / CHECK QUEUE"
            assert "FIXTURE_DETAIL="+expected_detail in result.stdout,(mode,result.stdout)
        print("TV_QUEUE_HTTP_PASS_"+mode)
    finally:
        server.shutdown();server.server_close();thread.join()
for mode in ("resume-play","empty-play","bad-count-play","main-preempt-read-pause","main-preempt-items-next","main-busy-mutation","pause","play","read","raw-pause","raw-play","raw-read","owner-change","owner-after-send","ambiguous","grouped","denied","wrong-queue","wrong-message","main-pause","main-play","main-read","main-raw-pause","main-raw-read","items","raw-items","items-wrong","items-too-many","main-items","main-raw-items","main-busy-items","main-busy-close","eof-discovery","stall-discovery","eof-command","truncated-command","server-error-command","stall-command","main-eof-command"):
    if not os.environ.get("TVQ_CASE") or os.environ["TVQ_CASE"]==mode: run(mode)
