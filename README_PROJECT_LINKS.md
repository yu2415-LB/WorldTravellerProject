# Infrastruttura di World Traveller — cosa NON si vede in questa cartella

Questo file spiega tutto ciò che fa funzionare il progetto ma che non è
scritto da nessuna parte nel codice: configurazioni fatte a mano su
Netlify, GitHub e Supabase. Se un giorno riparti da zero (nuovo computer,
nuovo collaboratore, account perso), questa è la mappa per ricostruire
tutto senza dover ricordare a memoria cosa avevamo fatto.

---

## 1. GitHub — dove vive il codice

**Repository:** `https://github.com/lorenzobaravelli/WTP.git`
**Branch principale:** `master`

### Cose da sapere che non sono ovvie guardando i file

- Il **remote** è già configurato in locale (`git remote -v` lo conferma),
  quindi `git push origin master` funziona così com'è, senza bisogno di
  ri-collegare nulla.
- **`.gitignore`** esclude `*.zip`: questo non è un dettaglio a caso — la
  cronologia Git è stata **ripulita da zero una volta** perché uno zip da
  270 MB era finito per sbaglio nei commit (GitHub rifiuta file oltre i
  100 MB). Se in futuro rivedi un errore simile ("File ... exceeds
  GitHub's file size limit"), la soluzione è sempre la stessa: togliere il
  file grosso dalla cartella, verificare il `.gitignore`, cancellare la
  cartella `.git` e reinizializzare con `git init` + un unico commit
  pulito, poi `git push -u origin master --force`.
- La cartella ha una struttura annidata insolita:
  `WorldTravellerProject/world_traveller_project/` (il progetto Flutter
  vero e proprio è nella sotto-cartella, non nella root del repo). Netlify
  è configurato per saperlo (vedi sotto) — se mai sposti i file, ricorda
  di aggiornare anche `base` in `netlify.toml`.

### Cosa NON è su GitHub

Le chiavi Supabase **sono** nel codice (`lib/main.dart`), ma va bene così:
è la chiave "publishable/anon", pensata apposta per stare in un'app
client-side pubblica — non è un segreto. Non c'è invece nessuna service
role key, password o chiave privata da nessuna parte nel repo.

---

## 2. Netlify — dove vive il sito online

Il sito è pubblicato leggendo `netlify.toml`, che sta dentro
`world_traveller_project/` e contiene già tutto il necessario:

```toml
[[plugins]]
  package = "netlify-plugin-flutter"

[build]
  publish = "build/web"
  command = "flutter build web --release"
```

### Perché c'è quel plugin

I server di build di Netlify **non hanno Flutter installato di default**.
`netlify-plugin-flutter` è quello che scarica e installa l'SDK Flutter
prima di lanciare `flutter build web --release`. Senza quel plugin, ogni
build fallirebbe con un errore tipo "flutter: command not found".

### Come è collegato

Il sito Netlify è collegato **direttamente al repository GitHub**: ogni
`git push` su `master` fa partire automaticamente una nuova build e un
nuovo deploy. Non c'è bisogno di caricare file a mano.

Cose configurate nella dashboard di Netlify (non nei file):

- Il repository GitHub collegato (`lorenzobaravelli/WTP`).
- La **directory base** impostata sulla sotto-cartella
  `world_traveller_project/`, visto che il progetto Flutter non è nella
  root del repo.
- Il nome del sito / dominio `.netlify.app` (o un dominio personalizzato,
  se ne è stato collegato uno da Site settings → Domain management).

### Se devi ricollegare tutto da zero

1. Netlify → "Add new site" → "Import an existing project" → GitHub →
   seleziona `lorenzobaravelli/WTP`.
2. Imposta la base directory su `world_traveller_project`.
3. Build command e publish directory li legge già da `netlify.toml`,
   quindi non serve reinserirli a mano.

### Alternativa senza Git (deploy manuale)

Se mai serve un deploy veloce senza passare da GitHub: `flutter build web
--release` in locale, poi trascinare la cartella `build/web` (non
l'intero progetto) su Netlify → "Add new site" → "Deploy manually". Utile
per test, ma niente aggiornamento automatico.

---

## 3. Supabase — dove vivono dati, utenti e foto

**URL progetto:** `https://jnxdelressqbbeakaglh.supabase.co`
(la trovi anche hardcoded in `lib/main.dart`, insieme alla chiave
pubblica — è normale che sia lì, vedi sopra).

Tutto quello che segue è stato configurato **a mano nella dashboard
Supabase** o **eseguito come script SQL**, e non è visibile guardando
solo il codice Flutter.

### 3.1 Tabelle del database

| Tabella | A cosa serve |
|---|---|
| `locations` | I pin sulla mappa (città, paese, coordinate, chi li ha creati) |
| `media_items` | Le singole foto, collegate a una `location` e a chi le ha caricate |
| `profiles` | Username univoco, email, bio, **ruolo** (`user`/`admin`) e stato di blocco per ogni account |
| `favourites` | Quali foto ogni utente ha messo tra i preferiti |

Le prime due (`locations`, `media_items`) esistevano già dal progetto
originale; `profiles` e `favourites` sono state create da
**`SUPABASE_SETUP.sql`**, e le colonne `role`/`is_blocked` sono state
aggiunte dopo da **`SUPABASE_SETUP_V2.sql`**. Questi due file SQL sono
nella cartella del progetto: se un giorno devi ricreare il database da
zero, vanno eseguiti in quest'ordine nell'SQL Editor di Supabase.

### 3.2 Permessi (Row Level Security)

Ogni tabella ha regole che decidono chi può leggere/scrivere cosa:

- Chiunque può **leggere** profili, foto e location (per mostrare la
  mappa anche a chi non è loggato).
- Un utente normale può modificare/eliminare **solo le sue** foto e i
  suoi pin.
- Un **admin** può modificare/eliminare le foto e i pin di chiunque —
  questo vale anche sui file dentro lo Storage, non solo sulle righe del
  database.
- Un utente **non può auto-promuoversi admin** né auto-sbloccarsi: un
  trigger SQL (`protect_privileged_profile_columns`) blocca il tentativo
  anche se qualcuno prova a chiamare l'API direttamente, scavalcando
  l'app.

Tutte queste regole sono scritte nei due file SQL sopra citati — se le
modifichi dalla dashboard Supabase invece che dal file, **ricorda di
aggiornare anche il file SQL**, altrimenti chi ricostruisce il database
da zero in futuro perderà quelle modifiche.

### 3.3 Storage

**Bucket:** `media`, impostato come **pubblico** (altrimenti le foto
caricate non si vedrebbero). I file sono organizzati come
`<user_id>/<location_id>/<nome_file>` — questa struttura di cartelle è
anche il modo in cui le policy di sicurezza capiscono di chi è un file
(il primo pezzo del percorso).

### 3.4 Autenticazione

- **Conferma email disattivata** (Authentication → Sign In / Providers →
  Email → "Confirm email" OFF) — comodo in fase di test, da rivalutare se
  il progetto va in produzione con utenti reali.
- **Google Sign-In**: se attivato, richiede due configurazioni esterne al
  codice — un OAuth Client ID creato su Google Cloud Console, e le sue
  credenziali incollate in Supabase dashboard → Authentication →
  Providers → Google. Nessuna di queste due cose è nei file del progetto.

### 3.5 Il primo account admin

Non esiste più un admin "fisso" via email hardcoded: il ruolo è nella
colonna `profiles.role`. Il primissimo admin è stato nominato con
un'istruzione SQL eseguita a mano (dentro `SUPABASE_SETUP_V2.sql`, in
fondo al file) che assegna `role = 'admin'` a un account specifico
tramite la sua email. Da quel momento in poi, nuovi admin si nominano
dal pannello Admin dentro l'app stessa — non serve più toccare SQL.

**Se perdi l'accesso admin** (account eliminato, email dimenticata):
vai nell'SQL Editor di Supabase ed esegui di nuovo quella query,
sostituendo l'email con un account che esiste ancora.

---

## 4. Riepilogo: cosa serve per ripartire da zero

Se dovessi ricostruire tutto su un account Netlify/Supabase/GitHub nuovo:

1. **GitHub**: crea un repo, fai push del codice (struttura a due
   cartelle annidate compresa).
2. **Supabase**: crea un progetto, esegui `SUPABASE_SETUP.sql` poi
   `SUPABASE_SETUP_V2.sql` (con la tua email al posto del placeholder),
   crea il bucket Storage `media` pubblico, disattiva la conferma email,
   copia URL e chiave pubblica del progetto in `lib/main.dart`.
3. **Netlify**: collega il repo GitHub, imposta la base directory sulla
   sotto-cartella del progetto Flutter, lascia che `netlify.toml` faccia
   il resto.

Tutti i dettagli tecnici di ogni passaggio sono nel file `SETUP_GUIDE.md`.
