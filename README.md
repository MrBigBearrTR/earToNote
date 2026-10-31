# earToNote

iPhone ve iPad için toplantı kayıt uygulaması. Toplantıya girerken kaydı başlatırsınız; kayıt bitince
uygulama konuşulanları yazıya döker, kimin ne söylediğini ayırır ve konuşmacıları toplantılar arasında
hatırlar. **Ses, metin ve ses imzaları yalnızca cihazda saklanır; hiçbir şey sunucuya gönderilmez.**

## Özellikler

- **Tek dokunuşla kayıt:** Ekran kilitliyken de devam eder. Duraklatıp devam ettirebilirsiniz; telefon
  araması gibi kesintilerden sonra kayıt otomatik olarak sürer.
- **Cihaz üzerinde yazıya dökme:** Apple'ın `SpeechAnalyzer` altyapısı (iOS 26) kullanılır. Varsayılan
  dil Türkçe; Ayarlar'dan İngilizce, Almanca veya Fransızca seçilebilir. `SpeechTranscriber` Türkçe'yi
  desteklemediği için Türkçe kayıtlar aynı altyapının `DictationTranscriber` modülüyle, yine cihaz üzerinde
  yazıya dökülür.
- **Konuşmacı ayrıştırma:** [FluidAudio](https://github.com/FluidInference/FluidAudio) ile (pyannote
  community-1 segmentasyonu, WeSpeaker ses imzaları ve VBx kümeleme, Core ML üzerinde) "kim ne zaman
  konuştu" bulunur.
- **Kişileri hatırlama:** Bir kişiye "Konuşmacı 1" yerine "Ali" adını verdiğinizde, Ali sonraki
  toplantılarda kaçıncı sırada konuşursa konuşsun yine "Ali" olarak yazılır.
- **Düzeltme araçları:** İsim değiştirme, "bu ses aslında başka biri" diyerek doğru kişiye atama, yeni
  kişi olarak ayırma, aynı kişinin iki kaydını birleştirme.
- **Metni alma:** Tüm metni tek dokunuşla kopyalama, `.txt` veya `.md` olarak paylaşma, metinden parça
  seçip kopyalama ve ses dosyasını paylaşma.
- **Dinleme:** Bir konuşmanın zaman damgasına dokunarak kaydın o anına gidebilirsiniz; çalan konuşma
  vurgulanır.
- **Arama:** Toplantı başlığı, kişi adı veya konuşma metninde arama.
- **Arka planda işleme:** Uygulamadan çıksanız da işlem iOS'un sistem ilerleme göstergesiyle bir süre
  devam eder.

## Konuşmacılar nasıl hatırlanıyor?

1. Kayıt bitince yazıya dökme ve konuşmacı ayrıştırma aynı anda çalışır. Kelimeler zaman damgalarına göre
   konuşmacılara dağıtılır.
2. Her konuşmacı için 256 boyutlu bir **ses imzası** (embedding) hesaplanır.
3. Bu imzalar cihazda kayıtlı kişilerin imzalarıyla kosinüs benzerliğiyle karşılaştırılır. Eşleşme bire
   birdir: bir toplantıda iki ses aynı kişiye atanamaz.
4. Eşleşen ses o kişinin adıyla yazılır ve kişinin ses imzası bu toplantıdaki sesle güncellenir
   (konuşma süresine göre ağırlıklı ortalama). Eşleşmeyen ses yeni bir **Konuşmacı N** olur; numaralar
   tüm toplantılar boyunca tektir.
5. İsim verdiğiniz kişi tüm toplantılarda o isimle görünür. Yanlış eşleşmeleri toplantı ekranında kişiye
   dokunarak düzeltebilirsiniz; düzeltme ses imzasına da yansır ve sonraki toplantılarda tanıma
   iyileşir.

Eşleşme hassasiyeti Ayarlar'dan değiştirilebilir. Farklı kişiler aynı isimle eşleşiyorsa değeri artırın,
aynı kişi her toplantıda yeni bir konuşmacı olarak geliyorsa azaltın.

## Gereksinimler

- Xcode 26 veya üzeri yüklü bir Mac.
- iOS 26 / iPadOS 26 çalışan, cihaz üzerinde konuşma tanımayı (`SpeechAnalyzer`) destekleyen bir
  iPhone veya iPad. Seçilen dil desteklenmiyorsa Ayarlar'da "Bu dil desteklenmiyor" yazar.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (Xcode projesi `project.yml` dosyasından üretilir).

## Kurulum

```bash
brew install xcodegen
git clone https://github.com/MrBigBearrTR/earToNote.git
cd earToNote
xcodegen generate
open EarToNote.xcodeproj
```

1. Xcode'da **EarToNote** hedefini seçin, **Signing & Capabilities** sekmesinde kendi **Team**'inizi
   seçin. Ücretsiz Apple hesabı da yeterlidir.
2. `com.eartonote.app` paket kimliği kullanılamıyorsa `project.yml` içindeki `PRODUCT_BUNDLE_IDENTIFIER`
   değerini değiştirip `xcodegen generate` komutunu tekrar çalıştırın.
3. Cihazınızı bağlayıp **Run** ile yükleyin. İlk açılışta mikrofon izni istenir.

`project.yml` veya klasör yapısı değiştiğinde `xcodegen generate` komutunu tekrar çalıştırın. Oluşan
`EarToNote.xcodeproj` ve `EarToNote/Info.plist` dosyaları git'e eklenmez.

## İlk kullanım

Yazıya dökme ve konuşmacı ayrıştırma modelleri bir kez internetten indirilir, sonrasında her şey internet
olmadan çalışır. Modelleri önceden indirmek için **Ayarlar > Modelleri Şimdi İndir**'e dokunun.
İndirmezseniz ilk toplantı işlenirken otomatik olarak indirilir. Bu nedenle ilk toplantının işlenmesi
daha uzun sürer.

- Konuşma tanıma modeli iOS'un sistem dil paketidir ve diğer uygulamalarla paylaşılır.
- Konuşmacı ayrıştırma modelleri FluidAudio tarafından HuggingFace'ten indirilip cihazda saklanır.

## Kullanım

1. **Kayıt Başlat**'a dokunun. Toplantı bitince kırmızı kare (durdur) düğmesine basın.
2. Kayıt otomatik olarak işlenir; ilerlemeyi listede ve toplantı ekranında görebilirsiniz.
3. Toplantı ekranındaki kişi etiketlerine veya metindeki isimlere dokunarak konuşmacıları adlandırın.
4. Sağ üstteki kopyala düğmesiyle tüm metni kopyalayın ya da **Diğer** (…) menüsünden paylaşın.
5. Kayıtlı tüm kişileri ana ekrandaki **Kişiler** düğmesinden yönetebilirsiniz (isim değiştirme,
   birleştirme, silme).

## Sınırlamalar

- Aynı anda konuşulan bölümlerde konuşmacı ayrımı ve metin doğruluğu düşer.
- Toplam 3 saniyeden kısa konuşan kişilerin ses imzası güvenilir olmadığı için kaydedilmez; bu kişiler
  sonraki toplantılarda otomatik tanınmayabilir.
- Sesi çok benzeyen kişiler veya çok farklı ortamlarda (hoparlör, telefon, gürültülü salon) yapılan
  kayıtlar yanlış eşleşmeye yol açabilir. Düzeltmeleriniz ses imzasını iyileştirir.
- Uzun kayıtların işlenmesi birkaç dakika sürebilir. iOS, uygulama arka plandayken işlemi bir süre sonra
  durdurabilir; bu durumda toplantı ekranından **Tekrar Dene** ile yeniden başlatabilirsiniz.

## Proje yapısı

```
project.yml                      XcodeGen proje tanımı (iOS 26, iPhone + iPad)
EarToNote/
  App/                           Uygulama girişi ve ayarlar
  Models/                        SwiftData modelleri (Meeting, TranscriptSegment, MeetingParticipant,
                                 SpeakerProfile) ve kişi yönetimi (SpeakerDirectory)
  Services/                      Ses kaydı, oynatma, yazıya dökme, konuşmacı ayrıştırma,
                                 işleme hattı (MeetingProcessor) ve arka plan görevi
  Views/                         SwiftUI ekranları
  Resources/                     Asset katalogu ve gizlilik bildirimi
Packages/MeetingCore/            Platformdan bağımsız mantık ve birim testleri:
                                 kelime-konuşmacı hizalama, ses imzası eşleştirme,
                                 metin birleştirme, dışa aktarma biçimleri
.github/workflows/ios-build.yml  CI: Linux ve macOS'ta testler, iOS Simulator derlemesi
```

## Testler

Uygulamanın platformdan bağımsız mantığı `MeetingCore` paketindedir; Xcode olmadan da (Linux dahil)
test edilebilir:

```bash
swift test --package-path Packages/MeetingCore
```

## Lisanslar

- [FluidAudio](https://github.com/FluidInference/FluidAudio): Apache 2.0. Kullanılan model lisansları
  için FluidAudio'nun [model kataloğuna](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Models.md)
  bakın.
