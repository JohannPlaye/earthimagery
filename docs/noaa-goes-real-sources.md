# 🛰️ NOAA GOES - Sources de données RÉELLES découvertes

## 📊 État des découvertes

### ✅ **Sources ACTIVES et accessibles**

#### 1. **STAR NESDIS CDN - Real-time Sectors** ⭐⭐⭐
- **URL**: `https://cdn.star.nesdis.noaa.gov/GOES16/ABI/SECTOR/`
- **Status**: ✅ ACTIF (données du 28 juillet 2025)
- **Format**: Images sectorielles en temps quasi-réel
- **Accès**: PUBLIC, pas d'authentification

**Secteurs disponibles:**
```
cam/  - Central America
can/  - Canada  
car/  - Caribbean
cgl/  - Central Great Lakes
eep/  - Eastern Pacific
eus/  - Eastern United States
ga/   - Gulf of Alaska
gm.0/ - Gulf of Mexico (backup)
mex/  - Mexico
na/   - North America
ne/   - Northeast US
nr/   - Northern Rockies
nsa/  - Northern South America
pnw/  - Pacific Northwest
pr/   - Puerto Rico
psw/  - Pacific Southwest
se/   - Southeast US
smv/  - Southern Mississippi Valley
sp/   - Southern Plains
sr/   - Southern Rockies
ssa/  - Southern South America
taw/  - Tropical Atlantic West
umv/  - Upper Mississippi Valley
```

**Structure supposée:**
```
https://cdn.star.nesdis.noaa.gov/GOES16/ABI/SECTOR/{secteur}/
├── GÉOCOLOR/     # Images couleur naturelle
├── Band02/       # Canal visible (0.64 μm)
├── Band13/       # Canal infrarouge (10.3 μm)
└── ...
```

#### 2. **SATEPS NESDIS - Archives et produits spécialisés** ⭐⭐
- **URL**: `https://satepsanone.nesdis.noaa.gov/pub/`
- **Status**: ✅ ACTIF (dernière MAJ: 28 juillet 2025)
- **Content**: Archives multiples, données spécialisées
- **Accès**: PUBLIC

**Répertoires intéressants:**
- `SR/` - Données satellite récentes (MAJ aujourd'hui)
- `MTCSWA/` - Multi-platform Tropical Cyclone Surface Wind Analysis
- `FIRE/` - Détection d'incendies
- `GOES13/`, `GOES15/` - Anciens satellites

### ❌ **Sources NON-ACCESSIBLES actuellement**

#### Buckets S3 AWS principaux
- `s3://noaa-goes16/` - Erreurs 404 sur tous les produits
- `s3://noaa-goes17/` - Erreurs 404 sur tous les produits  
- `s3://noaa-goes18/` - Erreurs 404 sur tous les produits

**Cause probable**: 
- Données archivées ou déplacées
- Restrictions d'accès récentes
- Changement de structure des buckets

## 🎯 **Recommandations pour EarthImagery**

### **Approche Phase 1: Secteurs temps réel**
```bash
# Test d'accès aux secteurs
curl -L "https://cdn.star.nesdis.noaa.gov/GOES16/ABI/SECTOR/na/"
curl -L "https://cdn.star.nesdis.noaa.gov/GOES17/ABI/SECTOR/psw/"
curl -L "https://cdn.star.nesdis.noaa.gov/GOES18/ABI/SECTOR/pnw/"
```

### **Structure de données supposée**
```
GOES16/ABI/SECTOR/na/GEOCOLOR/
├── 20250728/           # Date
│   ├── GOES16-ABI-na-GEOCOLOR-1000x1000.jpg
│   ├── GOES16-ABI-na-GEOCOLOR-2000x2000.jpg
│   └── GOES16-ABI-na-GEOCOLOR-5424x5424.jpg
└── latest.jpg
```

### **Zones géographiques optimales**

#### **Pour l'Europe** (via GOES16 depuis Atlantique)
- `eus/` - Eastern US (proche de l'Europe occidentale)
- `car/` - Caribbean (couverture Atlantique)
- `taw/` - Tropical Atlantic West

#### **Pour l'Amérique du Nord**
- `na/` - North America (couverture complète)
- `cgl/` - Central Great Lakes (haute densité population)
- `ne/` - Northeast (mégalopole Boston-Washington)

#### **Pour le Pacifique**
- `pnw/` - Pacific Northwest (Seattle, Vancouver)
- `psw/` - Pacific Southwest (Los Angeles, San Diego)
- `ga/` - Gulf of Alaska

## 🔧 **Plan d'implémentation**

### **Étape 1: Test de connectivité**
```bash
# Script de test de tous les secteurs
for sector in na ne se cgl psw pnw; do
    echo "Test $sector..."
    curl -L -s -w "%{http_code}" "https://cdn.star.nesdis.noaa.gov/GOES16/ABI/SECTOR/$sector/" -o /dev/null
done
```

### **Étape 2: Exploration de la structure**
```bash
# Une fois un secteur identifié comme actif
curl -L "https://cdn.star.nesdis.noaa.gov/GOES16/ABI/SECTOR/na/" | grep -E "\.(jpg|png|gif)"
```

### **Étape 3: Intégration dans real-data-helpers.sh**
```bash
fetch_goes_sector() {
    local satellite="$1"    # goes16, goes17, goes18
    local sector="$2"       # na, ne, psw, etc.
    local product="$3"      # GEOCOLOR, Band02, etc.
    local output="$4"
    
    url="https://cdn.star.nesdis.noaa.gov/${satellite}/ABI/SECTOR/${sector}/${product}/latest.jpg"
    fetch_image_with_auth "$url" "$output"
}
```

## 📈 **Avantages de cette approche**

### ✅ **Bénéfices**
- **Temps réel**: Données actualisées fréquemment  
- **Haute résolution**: Images sectorielles détaillées
- **Pas d'authentification**: Accès public simple
- **Multiple satellites**: GOES 16, 17, 18 disponibles
- **Couverture géographique**: Amériques + Atlantique + Pacifique

### ⚠️ **Limitations**
- **Couverture limitée**: Pas de couverture Europe/Afrique/Asie directe
- **Secteurs fixes**: Pas de full-disk global
- **Format inconnu**: Structure exacte à découvrir
- **Stabilité**: Dépendant de la politique NOAA

## 🚀 **Prochaines étapes**

1. **Reconnaissance détaillée** des secteurs actifs
2. **Identification des formats** d'images disponibles  
3. **Test de fréquence** de mise à jour
4. **Intégration** dans le pipeline de données réelles
5. **Fallback** vers sources EUMETSAT pour couverture globale

## 📝 **Notes techniques**

- **Protocole**: HTTPS avec redirections (utiliser `curl -L`)
- **Format supposé**: JPEG pour secteurs, possiblement NetCDF pour données brutes
- **Résolution**: Multiple résolutions probablement disponibles
- **Timing**: Mise à jour probable toutes les 5-15 minutes
- **Bande passante**: Images sectorielles plus légères que full-disk
