using Soup;
using GLib;
using Gdk;
using Json;

public class Olifant.Network : GLib.Object {

    public const string INJECT_TOKEN = "X-HeyMate-PlsInjectToken4MeThx";

    public signal void started ();
    public signal void finished ();
    public signal void notification (API.Notification notification);
    public signal void status_removed (string id);

	public delegate void ErrorCallback (int32 code, string reason);
	public delegate void SuccessCallback (Session session, Message msg) throws GLib.Error;

    private int requests_processing = 0;
    private Soup.Session session;

    construct {
        session = new Soup.Session ();
        session.ssl_strict = true;
        session.ssl_use_system_ca_file = true;
        session.timeout = 15;
        session.max_conns = 20;
        session.request_unqueued.connect (msg => {
            requests_processing--;
            if (requests_processing <= 0)
                finished ();
        });

        // Soup.Logger logger = new Soup.Logger (Soup.LoggerLogLevel.BODY, -1);
        // session.add_feature (logger);
    }

    public Network () {}

    public async WebsocketConnection stream (Soup.Message msg) throws GLib.Error {
        return yield session.websocket_connect_async (msg, null, null, null);
    }

    public void cancel_request (Soup.Message? msg) {
        if (msg == null)
            return;
        switch (msg.status_code) {
            case Soup.Status.CANCELLED:
            case Soup.Status.OK:
                return;
        }
        session.cancel_message (msg, Soup.Status.CANCELLED);
    }

    public void inject (Soup.Message msg, string header) {
        msg.request_headers.append (header, "VeryPls");
    }

    private void inject_headers (ref Soup.Message msg) {
        var headers = msg.request_headers;
        var formal = accounts.formal;
        if (headers.get_one (INJECT_TOKEN) != null) {
            headers.remove (INJECT_TOKEN);
        }
        if (formal != null) {
            headers.append ("Authorization", "Bearer " + formal.token);
        }
    }

    public void queue (owned Soup.Message message, owned SuccessCallback? cb = null, owned ErrorCallback? errcb = null) {
        requests_processing++;
        started ();

        inject_headers (ref message);

        session.queue_message (message, (sess, msg) => {
        	var status = msg.status_code;
            if (status != Soup.Status.CANCELLED) {
            	if (status == Soup.Status.OK) {
            		if (cb != null) {
            		    try {
            		        cb (session, msg);
            		    }
            		    catch (Error e) {
            		        warning ("Caught exception on network request:");
            		        warning (e.message);
                    		if (errcb != null)
                    			errcb (Soup.Status.NONE, e.message);
            		    }
            		}
            	}
            	else {
            		if (errcb != null)
                        errcb ((int32)status, get_error_reason ((int32)status));
            	}
            }
            // msg.request_body.free ();
            // msg.response_body.free ();
            // msg.request_headers.free ();
            // msg.response_headers.free ();
        });
    }

    public void queue_noauth (owned Soup.Message message, owned SuccessCallback? cb = null, owned ErrorCallback? errcb = null) {
        requests_processing++;
        started ();

        session.queue_message (message, (sess, msg) => {
        	var status = msg.status_code;
            if (status != Soup.Status.CANCELLED) {
            	if (status == Soup.Status.OK) {
            		if (cb != null) {
            		    try {
            		        cb (session, msg);
            		    }
            		    catch (Error e) {
            		        warning ("Caught exception on network request:");
            		        warning (e.message);
                    		if (errcb != null)
                    			errcb (Soup.Status.NONE, e.message);
            		    }
            		}
            	}
            	else {
            		if (errcb != null)
                        errcb ((int32)status, get_error_reason ((int32)status));
            	}
            }
            // msg.request_body.free ();
            // msg.response_body.free ();
            // msg.request_headers.free ();
            // msg.response_headers.free ();
        });
    }

	public string get_error_reason (int32 status) {
		return "Error " + status.to_string () + ": " + Soup.Status.get_phrase (status);
	}

    public void on_error (int32 code, string message) {
        warning (message);
        app.toast (message);
    }

    public void on_show_error (int32 code, string message) {
    	warning (message);
    	app.error (_("Network Error"), message);
    }

    public Json.Object parse (Soup.Message msg) throws GLib.Error {
        // debug ("Status Code: %u", msg.status_code);
        // debug ("Message length: %lld", msg.response_body.length);
        // debug ("Object: %s", (string) msg.response_body.data);

        var parser = new Json.Parser ();
        parser.load_from_data ((string) msg.response_body.flatten ().data, -1);
        return parser.get_root ().get_object ();
    }

    public Json.Array parse_array (Soup.Message msg) throws GLib.Error {
        // debug ("Status Code: %u", msg.status_code);
        // debug ("Message length: %lld", msg.response_body.length);
        // debug ("Array: %s", (string) msg.response_body.data);

        var parser = new Json.Parser ();
        parser.load_from_data ((string) msg.response_body.flatten ().data, -1);
        return parser.get_root ().get_array ();
    }
    
    //TODO: Cache
    public delegate void PixbufCallback (Gdk.Pixbuf pixbuf);
    public Soup.Message load_pixbuf (string url, PixbufCallback cb, owned ErrorCallback? errcb = null, int? size = null) {
        var message = new Soup.Message("GET", url);
        network.queue_noauth (
            message, 
            (sess, msg) => {
                Gdk.Pixbuf? pixbuf = null;
                try {
                    var data = msg.response_body.flatten ().data;
                    var stream = new MemoryInputStream.from_data (data);
                    if (size == null)
                        pixbuf = new Gdk.Pixbuf.from_stream (stream);
                    else 
                        pixbuf = new Gdk.Pixbuf.from_stream_at_scale (stream, size, size, true);
                }
                catch (Error e) {
                    warning ("Can't decode image: %s".printf (url));
                    warning ("Reason: " + e.message);
                }
                cb (pixbuf);
            },
            (status, status_message) => {
                warning ("Could not get an image %s with http status: %i".printf (url, status));
                if (errcb != null)
                    errcb (status, status_message);
            }
        );
        return message;
    }

    public void load_image (string url, Gtk.Image image) {
        load_pixbuf(
            url,
            image.set_from_pixbuf,
            (_, __) => {
                image.set_from_icon_name ("image-missing", Gtk.IconSize.LARGE_TOOLBAR);
            }
        );
    }

    public void load_scaled_image (string url, Gtk.Image image, int size) {
        load_pixbuf(
            url,
            image.set_from_pixbuf,
            (_, __) => {
                image.set_from_icon_name ("image-missing", Gtk.IconSize.LARGE_TOOLBAR);
            },
            size
        );
    }

    public void load_avatar (string url, Granite.Widgets.Avatar avatar, int size){
        load_pixbuf(
            url,
            (pixbuf) => { avatar.pixbuf = pixbuf.scale_simple (size, size, Gdk.InterpType.BILINEAR); },
            (_, __) => { avatar.show_default (size); },
            size
        );
    }

}
