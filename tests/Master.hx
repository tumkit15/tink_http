package;

import haxe.CallStack;
import neko.vm.Thread;
import sys.net.Host;
import sys.net.Socket;
import sys.io.File;

class Master {
	
	public static var port = 8000;
	static var originalHxml:String;
	
	public static function main() {
		checkPort(port);
		originalHxml = File.getContent('tests.hxml');
		
		var containers: String = Env.getDefine('containers');
		if (containers == null)
			fail('No containers set, use -D containers=php,neko');
		var targets: String = Env.getDefine('targets');
		if (targets == null)
			fail('No targets set, use -D targets=php,neko');
		
		var result = true;
		for (container in containers.split(',')) {
			if (!Context.containers.exists(container))
				fail('Container $container not available');
			
			var server = Context.containers.get(container);
			try {
				Sys.println(Ansi.text(Cyan, '\n>> Building container $container'));
				var process = server(port);
				waitForConnection(port);
				
				for (target in targets.split(',')) {
					if (!Context.targets.exists(target)) {
						Ansi.fail('No such target: $target');
						continue;
					}
					Sys.println(Ansi.text(Yellow, '\n>> Running target $target'));
					var runner = Context.targets.get(target)(port);
					var code = runner.exitCode();
					if (code != 0)
						Ansi.fail('$target failed');
					result = result && code == 0;
					if (!result) break;
				}
				
				close(port);
				process.kill();
			} catch(e: Dynamic) {
				Sys.println(e);
				Sys.print(CallStack.toString(CallStack.exceptionStack()));
			}
		}
		
		restoreHxml();
		Sys.sleep(.01);
		Sys.exit(result ? 0 : 1);
	}
	
	static function restoreHxml() {
		if(originalHxml != null) File.saveContent('tests.hxml', originalHxml);
	}

	static function fail(msg) {
		Ansi.fail(msg);
		restoreHxml();
		Sys.exit(1);
	}

	static function close(port: Int) {
		var http = new haxe.Http('http://127.0.0.1:$port/close');
		http.onData = function(_) null;
		http.request();
	}
	
	static function waitForConnection(port: Int) {
		var connected = false;
		Thread.create(function() {
		var i = 60*4;
				while (i > 0) {
			i--;
			Sys.sleep(1);
		}
		if (!connected)
			fail('Could not connect to server (timeout: ${i}s)');
			});
			var i = 0;
			while (i < 20) {
				var http = new haxe.Http('http://127.0.0.1:'+port+'/active');
				var result = false;
				http.onData = function(_) result = true;
				http.request();
				if (result) {
			connected = true;
			return true;
		} else {
			Sys.sleep(.1);
		}
			}
			fail('Could not connect to server');
		return false;
	}

	static function checkPort(port: Int) {
		var socket = new Socket();
		try {
			socket.connect(new Host('127.0.0.1'), port);
			fail('Another process is already bound to port $port');
		} catch (e: Dynamic) {}
	}
	
}