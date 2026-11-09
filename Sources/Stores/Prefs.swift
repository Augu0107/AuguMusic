import Foundation

/// Chiavi delle preferenze "di dettaglio" (Interfaccia, menù...). Si leggono con @AppStorage nelle viste
/// e con `Prefs.bool/string/...` nel codice che non è una vista. I valori predefiniti sono registrati
/// all'avvio, così le due strade danno sempre lo stesso risultato.
enum Prefs {
    // Interfaccia
    static let tabBarTop = "ui.tabBarTop"
    static let tabOrder = "ui.tabOrder"

    // Code
    static let queueArtwork = "queue.artwork"
    static let queueSwipeRemove = "queue.swipeRemove"
    static let queueSearch = "queue.search"
    static let queueRemoveOthers = "queue.removeOthers"

    // In riproduzione
    static let npRemaining = "np.remaining"
    static let npSwipe = "np.swipe"
    static let npBlur = "np.blur"
    static let lyricsSize = "lyrics.size"
    static let lyricsAlign = "lyrics.align"
    static let lyricsSerif = "lyrics.serif"
    static let lyricsKeepAwake = "lyrics.keepAwake"
    static let npArtTap = "np.artTap"
    static let npShowArtist = "np.showArtist"
    static let npShowAlbum = "np.showAlbum"
    static let npIcons = "np.icons"
    static let npCentered = "np.centered"
    static let npMarquee = "np.marquee"
    static let npSeekButtons = "np.seekButtons"
    static let npSeekHelpers = "np.seekHelpers"
    static let npThumbOnly = "np.thumbOnly"
    static let npMonthlyHint = "np.monthlyHint"

    // Cartelle
    static let foldersSearch = "folders.search"
    static let foldersInfo = "folders.info"
    static let foldersHierarchical = "folders.hierarchical"
    static let excludedFolders = "folders.excluded"

    // Album
    static let albumsView = "albums.view"
    static let albumsGridSize = "albums.gridSize"
    static let albumsInfo = "albums.info"
    static let albumsSplit = "albums.split"
    static let albumsSearch = "albums.search"

    // Artisti
    static let artistsInfo = "artists.info"
    static let artistsSplit = "artists.split"
    static let artistsAlbumSort = "artists.albumSort"
    static let artistsSearch = "artists.search"

    // Genere
    static let genresInfo = "genres.info"
    static let genresSplit = "genres.split"
    static let genresSearch = "genres.search"

    // Playlist
    static let playlistsSearch = "playlists.search"

    // Opzioni e menù (elenchi di voci attive, separate da virgola)
    static let menuMain = "menu.main"
    static let menuQuick = "menu.quick"
    static let menuNowPlaying = "menu.nowPlaying"
    static let menuTrack = "menu.track"
    static let menuMulti = "menu.multi"
    static let menuFolder = "menu.folder"
    static let menuAlbum = "menu.album"
    static let menuArtist = "menu.artist"
    static let menuGenre = "menu.genre"
    static let menuPlaylist = "menu.playlist"

    static let lastMonthlyHint = "np.lastMonthlyHint"

    static let defaults: [String: Any] = [
        tabBarTop: false,
        tabOrder: "",
        queueArtwork: true,
        queueSwipeRemove: true,
        queueSearch: true,
        queueRemoveOthers: true,
        npRemaining: false,
        npSwipe: true,
        npBlur: 3.0,
        lyricsSize: 0,
        lyricsAlign: 1,
        lyricsSerif: true,
        lyricsKeepAwake: true,
        npArtTap: "artwork",
        npShowArtist: true,
        npShowAlbum: true,
        npIcons: false,
        npCentered: true,
        npMarquee: true,
        npSeekButtons: "long",
        npSeekHelpers: true,
        npThumbOnly: false,
        npMonthlyHint: true,
        foldersSearch: true,
        foldersInfo: "duration",
        foldersHierarchical: false,
        excludedFolders: "",
        albumsView: "grid",
        albumsGridSize: 2,
        albumsInfo: "auto",
        albumsSplit: true,
        albumsSearch: true,
        artistsInfo: "duration",
        artistsSplit: true,
        artistsAlbumSort: "yearDesc",
        artistsSearch: true,
        genresInfo: "auto",
        genresSplit: true,
        genresSearch: true,
        playlistsSearch: true,
        menuMain: "equalizer,sleepTimer,scan,quit",
        menuQuick: "lyrics,favorite,equalizer,sleepTimer,speed,bookmarks",
        menuNowPlaying: "favorite,ab,crossfade,cast,tagEditor,replayGain,move",
        menuTrack: "share,tagEditor,speed,rg,move,delete,preview,stopAfter",
        menuMulti: "advShuffle,share,tagEditor,speed,rg,move,copy,delete,clearHistory",
        menuFolder: "rename,exclude,advShuffle,share,tagEditor,speed,rg",
        menuAlbum: "advShuffle,share,tagEditor,speed,rg",
        menuArtist: "advShuffle,share,tagEditor,speed,rg",
        menuGenre: "advShuffle,share,tagEditor,speed,rg",
        menuPlaylist: "advShuffle,share,tagEditor,speed,rg",
    ]

    static func register() {
        UserDefaults.standard.register(defaults: defaults)
    }

    static func bool(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }
    static func string(_ key: String) -> String { UserDefaults.standard.string(forKey: key) ?? "" }
    static func double(_ key: String) -> Double { UserDefaults.standard.double(forKey: key) }
    static func int(_ key: String) -> Int { UserDefaults.standard.integer(forKey: key) }
}

/// Elenco di voci attive salvato come "a,b,c".
extension String {
    var csvItems: Set<String> { Set(split(separator: ",").map(String.init)) }

    func csvContains(_ item: String) -> Bool { csvItems.contains(item) }

    static func csv(_ items: Set<String>) -> String { items.sorted().joined(separator: ",") }
}
