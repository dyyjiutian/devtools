// V2RayXS replaces the placeholders below when serving /proxy.pac.
// ${V2RAYXS_SOCKS} is replaced with the current local SOCKS proxy port.
// ${V2RAYXS_HTTP} is replaced with the current local HTTP proxy port.
var V2Ray = "SOCKS5 127.0.0.1:${V2RAYXS_SOCKS}; SOCKS 127.0.0.1:${V2RAYXS_SOCKS}; DIRECT;";

var domains = [
    'chrome-devtools-frontend.appspot.com',
	'analytics.google.com',
	'android.com',
	'packagist.org',
	'visualstudio.com',
	'laravel.com',
	'yarnpkg.com',
	'pinterest.com',
	'pinimg.com',
	'unsplash.com',
	'gitlab.com',
	'githubusercontent.com',
	'gradle.org',
	'bintray.com',
	'dribbble.com',
	'sketch.com',
	'cdn.cocoapods.org',
	'v2ex.com',
	'npmjs.com',
	'tiktok.com',
	'tiktokcdn.com',
    "cdn.dribbble.com",
    
	"vpngate.net",
	"greatfire.org",
	"tox.im",
	"proxifier.com",
	"dnscrypt.org",
	"atgfw.org",
	"chinagfw.org",
	"whatismyip.com",
	"goagentplus.com",
	"shadowsocks.org",
	"falcop.com",
	"getlantern.org",
	"furbo.org",
	"goagentx.com",
	"github.com",
	"sourceforge.net",
	"torproject.org",
	"hideme.io",
	"mozilla.org",
	"shadowx.work",
	"v2ray.com",
	"astrill.com",

	//Design
	"deviantart.com",

	"disqus.com",
	"disquscdn.com",
	"tumblr.com", 
	"flickr.com",
	"imgur.com",

	"evozi.com",
	"live.com",
	"1drv.com",
	"evernote.com",

	//blog
	"wp.com",
	"yam.com",
	"ashchan.com",
	"zuckclub.com",
	"blogspot.com",
	"blogspot.jp",
	"zalex2014.tk",
	"coreygilmore.com",
	"wordpress.com",
	"blogimg.jp",
	"leaskh.com",
	"blogger.com",
	"hexo.io",
	"medium.com",

	//GeneralNews
	"rfi.my",
	"rfi.fr",
	"washingtonpost.com",
	"tmagazine.com",
	"nytimes.com",
	"nytimg.com",
	"imrworldwide.com",
	"rankingsandreviews.com",
	"usnews.com",
	"bbc.co.uk",
	"bbci.co.uk",
	"bbc.com",
	"on-match.com",
	"solidot.org",

	//TechNews
	"engadget.com", 

	//Network
	"amazonaws.com",
	"fastly.net",
	"akamaihd.net", 
	"blogsmithmedia.com", 
	"bit.ly",
	"d.pr",
	"ow.ly",
	"ift.tt",

	"nateparrott.com",
	
	"stacksocial.com",
	"feedly.com",
	"acgtea.com",

	//academy and develop
	"ieee.org",
	"mathoverflow.net",
	"tex.stackexchange.com",
	"academia.edu",
	"geogebra.org",
	"golang.org",
	"netspeak.org",
	"endreslab.com",

	//Universities
	"illinois.edu",
	"berkeley.edu",
	"wisc.edu",
	"cmu.edu",
	"rochester.edu",
	"purdue.edu",
	"technolutions.net",

	"netflix.com",

	//Online Dictionary
	"ldoceonline.com",
	"freedicts.com",

	//Softwares
	"formacx.com",
	"trionworlds.com",
	"line.me",

	//otaku
	"e-hentai.org",
	"nhentai.net",
	"nicovideo.jp",
	"nimg.jp",
	"pixnet.net",
	"fc2.com",
	"nyaatorrents.org",
	"nyaa.se",
	"share.dmhy.org",
	"loli.us",

	//facebook
	"facebook.net",
	"instagram.com",
	"facebook.com",
	"fb.me", 
	"cdninstagram.com",
	"fbcdn.net", 

	"booth.pm",

	"telegram.org",
	"telegram.me",

	"wikipedia.org",
	"pixiv.net",
	"twitch.tv",

	//Twitter
	"twitter.com",  
	"t.co", 
	"twimg.com",

	//Google
	"gmail.com", 
	"googlemail.com",
	"mailchimp.com", 
	"mail-archive.com", 
	"google.com", 
	"goo.gl",
	"google.com.hk", 
	"google.com.tw", 
	"google.co.jp",
	"googlecode.com",
	"googleapis.com", 
	"ggpht.com",
	"youtube.com", 
	"youtu.be",
	"ytimg.com",
	"youtube-nocookie.com",
	"googlevideo.com",
	"sketchup.com",
	"gstatic.com",
	"google-analytics.com",
	"googleusercontent.com",
	"chrome.com", 
	"g.co", 
	"googledrive.com", 
	"googletagmanager.com", 
	"googleadservices.com",
	"abc.xyz",

	//Dropbox
	"dropbox.com",
	"dropboxusercontent.com",
	"dropboxwiki.com",

	//iTuens
	"mzstatic.com",
	"itunes.apple.com",

	//cdn
	"cloudfront.net",
	"colwiz.com",

	//AI - Anthropic / Claude
	"anthropic.com",
	"claude.ai",
	"claudeusercontent.com",

	//AI - OpenAI / ChatGPT
	"openai.com",
	"chatgpt.com",
	"oaiusercontent.com",
	"oaistatic.com",
	"sora.com",

	//AI - Google Gemini
	"ai.google.dev",
	"deepmind.com",
	"gemini.google.com",

	//AI - xAI / Grok
	"x.ai",
	"grok.com",

	//AI - Perplexity
	"perplexity.ai",

	//AI - Mistral
	"mistral.ai",

	//AI - Meta AI
	"meta.ai",
	"llama.meta.com",

	//AI - Hugging Face
	"huggingface.co",

	//AI - Midjourney + Discord
	"midjourney.com",
	"discord.com",
	"discordapp.com",
	"discordapp.net",
	"discord.gg",

	//AI - Character AI
	"character.ai",

	//AI - Poe
	"poe.com",

	//AI - Groq
	"groq.com",

	//AI - Cohere
	"cohere.com",

	//AI - Replicate
	"replicate.com",
	"replicate.delivery",

	//AI - Stability AI
	"stability.ai",
	"stablediffusionweb.com",
	"dreamstudio.ai",

	//AI - Runway ML
	"runwayml.com",
	"runway.com",

	//AI - ElevenLabs
	"elevenlabs.io",

	//AI - Cursor
	"cursor.sh",
	"cursor.com",

	//AI - Vercel / v0
	"vercel.com",
	"vercel.app",
	"v0.dev",

	//Apple & iCloud
	"apple.com",
	"icloud.com",
	"me.com",
	"cdn-apple.com",
	"apple-cloudkit.com",
	"appleusercontent.com",

	//Docker & Container
	"docker.com",
	"docker.io",
	"gcr.io",
	"ghcr.io",
	"k8s.io",
	"quay.io",
	"registry.k8s.io",
	"pkg.dev",

	//Microsoft / Azure / Office
	"microsoft.com",
	"microsoftonline.com",
	"office.com",
	"office365.com",
	"sharepoint.com",
	"onedrive.com",
	"windows.com",
	"xbox.com",
	"azure.com",
	"azureedge.net",
	"msftauth.net",
	"msauth.net",
	"msecnd.net",

	//E-Commerce
	"amazon.com",
	"amazon.co.jp",
	"amazon.co.uk",
	"amazon.de",
	"amazon.fr",
	"s3.amazonaws.com",
	"shopee.com",
	"shopee.sg",
	"shopee.co.id",
	"shopee.com.my",
	"shopee.ph",
	"shopee.co.th",
	"shopee.vn",
	"shopeemobile.com",
	"lazada.com",
	"ebay.com",
	"etsy.com",
	"paypal.com",
	"stripe.com",
	"wise.com",

	//Developer Tools
	"stackoverflow.com",
	"stackexchange.com",
	"superuser.com",
	"askubuntu.com",
	"serverfault.com",
	"dev.to",
	"hashnode.com",
	"codepen.io",
	"jsfiddle.net",
	"codesandbox.io",
	"replit.com",
	"jetbrains.com",
	"atlassian.com",
	"bitbucket.org",
	"cloudflare.com",
	"digitalocean.com",
	"heroku.com",
	"netlify.com",
	"netlify.app",
	"render.com",
	"railway.app",
	"supabase.com",
	"supabase.io",
	"neon.tech",
	"planetscale.com",

	//Communication
	"slack.com",
	"slack-edge.com",
	"zoom.us",
	"whatsapp.com",
	"whatsapp.net",
	"signal.org",
	"notion.so",
	"notion.com",
	"loom.com",
	"figma.com",
	"linear.app",
	"airtable.com",
	"typeform.com",
	"zapier.com",

	//Social
	"reddit.com",
	"redd.it",
	"redditstatic.com",
	"redditmedia.com",
	"reddit.it",
	"linkedin.com",
	"licdn.com",
	"quora.com",
	"threads.net",
	"producthunt.com",
	"ycombinator.com",
	"substack.com",
	"patreon.com",

	//Entertainment & Streaming
	"spotify.com",
	"scdn.co",
	"spotifycdn.com",
	"vimeo.com",
	"vimeocdn.com",
	"soundcloud.com",
	"canva.com",

	//Cloud Storage
	"box.com",
	"box.net",
	"mega.nz",
	"mega.co.nz",

	//Security & Privacy
	"protonmail.com",
	"proton.me",
	"protonvpn.com",
	"duckduckgo.com",
	"brave.com",
	"1password.com",
	"bitwarden.com",

	//Games
	"steampowered.com",
	"steamcommunity.com",
	"steamstatic.com",
	"steam-chat.com",
	"valve.com",
	"epicgames.com",
	"unrealengine.com",
	"blizzard.com",
	"battle.net",
	"ea.com",
	"origin.com",
	"riotgames.com"
];

function FindProxyForURL(url, host) {
    // Local and private addresses always go direct
    if (isPlainHostName(host) ||
        host === "localhost" ||
        isInNet(host, "127.0.0.0",   "255.0.0.0") ||
        isInNet(host, "10.0.0.0",    "255.0.0.0") ||
        isInNet(host, "172.16.0.0",  "255.240.0.0") ||
        isInNet(host, "192.168.0.0", "255.255.0.0") ||
        isInNet(host, "169.254.0.0", "255.255.0.0")) {
        return "DIRECT";
    }

    for (var i = domains.length - 1; i >= 0; i--) {
    	if (dnsDomainIs(host, domains[i])) {
            return V2Ray;
    	}
    }
    return "DIRECT";
}

