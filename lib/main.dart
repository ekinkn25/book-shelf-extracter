import 'package:flutter/material.dart'; //flutterın en temel ui kütüphanesidir googlenin material design tasarım dilini içerir(widget)
import 'package:image_picker/image_picker.dart';
import 'dart:io'; // dart dilinin standart input output kütüpanesidir 
//biz bunu  ileride seçtiğimiz resmi bir file objesi olarak tutmak ve okumak içn kullanacağız mobil uyg harika çalışır ama web tarayıcılarında dosya sist farklı old için webde doğrudan kullanılamaz
import 'package:flutter/foundation.dart' show kIsWeb; //bu bize şuan uygulamaının o an bi web tarayıcısında mı yoksa mobilde mi çalıştığını söyler, webdeysek resmi şöyle gönder mobildeysek böyle göster diyebilmek için ihtiyacımız var
import 'package:http/http.dart' as http; //http kullanmadan önce hep http. yazılacak 
import 'dart:convert';

void main() { //derleyici kodu ilk mainden okumaya başlar
  runApp(const MyApp()); //görevi içine verdiğimiz ana iskeleti MyApp alıp ekrana çizmektir (render etmek)
}

//flutterda her şey widget ekranda gördüğümüz buton metin ortalama hizalaması boşluk hepsi widget sınıfı ve iç içe geçerek bi widget ağacı oluştururlar
class MyApp extends StatelessWidget { //extends StatelessWidget  demek bu sınıftan türetiyoruz demek
//iki ana tür widget var 
//1)StatelessWidget (Durumsuz): Ekrana bir kere çizilir ve kendi iç dinamikleriyle değişmez (Örn: Sadece bir metin veya bir ikon)

//2)StatefulWidget (Durumlu): İçindeki veri değiştiğinde kendini yeniden ekrana çizebilen yapılar (Örn: Bir sayacın artması veya bir resmin yüklenip ekranda belirmesi).
  const MyApp({Key? key}) : super(key: key); //MyApp sınıfının kurucu (constructor) metodudur.
  //key : flutterin arka planda o widgeti tanımak ve takip etmek için kullandığı bir kimliktir 
  //const ise bu sınıf sabit beni bir daha baştan çizerek yorma der ve performansı arttırır

  @override
  Widget build(BuildContext context) {//flutterda her sınıf zorunlu build metodu olmalı bu fonksiyon erkana ne çizdireceğizi döndürür
  //BuildContext contextbu widgetin ağaç yapısında nerede old ebeveynleri kim
    return MaterialApp( //ana çatı MaterialApp(...)
      title: 'Library to Excel', //uygulamanın osteki adı webde çalışıtırırken de tarayıcı sekmesinde bu yazar telefonda ise arka planda çalışan uygulamalar menüsünde bu isim görünür
      debugShowCheckedModeBanner: false, //üstte sağda debug yazısı yazmasın der
      theme: ThemeData(
        primarySwatch: Colors.purple, // uygulamanın ana rengi butonlar yükleme animasyonları uyg barları vs aksi belirtilmedikçe mor olur 
        useMaterial3: true, //googlenin güncel moder ui kütüp olan material 3 standartlarını aktivite eder yumuşak köşeler modern renk atamaları
      ),
      home: const HomePage(), //uyg açıldığında ekrana gelecek ilk sayfayı ana sayfayı belirtir
    );
  }
}

class HomePage extends StatefulWidget { //reactdaki state mantığıyla aynıdır state değişebilir home pagede o yüzden stateful dedi
  const HomePage({Key? key}) : super(key: key);
  //dışarıdan parametre beklemiyoruz sadece arka planda flutterın bu sayfayı takip edebilmesi için bi key alıp üst sınıfa iletiyor

  @override
  State<HomePage> createState() => _HomePageState();
  //Flutterda statefulwidget iki parçadan oluşur 
  //1. widgetin kendisi HomePage: sadece konfigrasyonu tutar sabittir immutable
  //2. state nesnesi _HomePageState asıl veriyi seçilen resim vb ve ekranı çizen kodları tutar değişebilen mutable kısım burası
  //createState() fonskiyonu fluttera şunu der benim içimdeki veriler ve tasarımım _HomePageState adında başka sınıfa yönetilecek git onu oluştur der
  //alt tire şı anlama geliyor dart dişinde public private protected gibi şeyler yok onun yerine _ konulan değişken/fonk/sınıf o sadece bulunduğu dosta içinden erişilebilir yani private yani _homaPageState sınıfı sadece bu main.dart dosyası içinde yaşayabilir dışarıdan başka dosya onu çağıramaz encapsulation
} //özellikle bu blok diyor ki fluttera benim verilerim değişecek o yüzden ana bi state objesi bağla diyor ve işi _HomePageState sınıfına devrediyor. yani veriler _HomePAgeState sınıfında

class _HomePageState extends State<HomePage> {//HomePage widgetinin state classi, sayfanın hafızası, kullanıcı sayfadayken değişecek olan tüm veriler burada yaşar
  XFile? _selectedImage;
  //XFile bu image_picker paketinin sunduğu özel dosya türü, ? : dart is null-safe yani b uvariable içi şuan boş null olabilir demek 
  final ImagePicker _picker = ImagePicker();
  //instance alıyoruz başına final koyduk çünkü bu aletin referansı uyg çalıştığı sürece hiç değişmeyecek
  String? _extractedText; // API'den dönecek olan okunan yazıyı tutacak
  List<String> _bookLines = [];
  bool _isLoading = false; // "İnternete gitti, cevap bekliyoruz" animasyonu için
  final String apiKey = 'K86979645388957';
  // İnternetteki OCR servisine resmi gönderip yazıyı alma fonksiyonu
  Future<void> _extractTextFromImage() async {
    // Eğer resim seçilmemişse boşuna çalışma, geri dön
    if (_selectedImage == null) return;

    // Yükleniyor durumunu başlat (ekrana dönen çark koymak için)
    setState(() {
      _isLoading = true;
      _extractedText = null; // Eski yazıyı temizle
    });

    try {
      final bytes = await _selectedImage!.readAsBytes();
      
      // 2. Base64 formatına çevir (Resmi internette taşınabilir güvenli bir metne dönüştürür) bytlara çevirince sadece 0 ve 1leri görürüz ama base64Image yapınca string halinde değişik metinlere dönüşür 
      final String base64Image = "data:image/jpeg;base64," + base64Encode(bytes);//"data:image/jpeg;base64," kısmı şunu der ben apiden uzun bir metin gönderiyorum ama slında bu base64 ile şifrelenmiş bir jpeg remidir haberin olsun knk der

      // 3. Postacıyı (http) OCR.space adresine paketlerle beraber gönder
      var response = await http.post(
        Uri.parse('https://api.ocr.space/parse/image'),//burası diyor ki ben bu linke düz metin atıyorum ya burada eskid en sıkıntı çıkıyormuş o yüzden parse yani bölüyor https bir api.ocr.space ayrı /parse/image ayrı bölünüyor sonra da resim stringi ile Uri nesnesi oluşturup postacıya yani http.post teslim ediyor
        body: {
          'apikey': apiKey,
          'base64Image': base64Image,
          'language': 'eng', // Türkçe karakterleri (ş, ç, ğ) düzgün okuması için normalde tur yazıyordu 
          'scale' : 'true',
          'OCREngine': '5',
        },
      );

      // 4. API'den gelen İngilizce/JSON cevabı Flutter'ın anlayacağı sözlüğe (Map/Dictionary) çevirir artık elimizde key value ikililerden oluşan bi yapıda verir
      var result = jsonDecode(response.body);

      // 5. Eğer hata yoksa okunan metni al ve ekranı güncelle
      if (result['IsErroredOnProcessing'] == false) {
        setState(() {
          // ParsedResults içindeki ilk sayfanın ParsedText'ini alıyoruz (API'nin kuralı bu)
          _extractedText = result['ParsedResults'][0]['ParsedText'];//parsedresults kısmı apinin okuduğu sayfanın listesidir, [0] bizim gönderediğimiz resim tek sayfa old için listenin ilk elemannı alıyoruz zaten bir tane vardı; parsedtext o ilk sayfanın içindeki asıl okunan metin
          List<String> rawLines = _extractedText!.split('\n');
          _bookLines = rawLines.where((line)=> line.trim().length>2).toList();
        });
      } else {
        // API bir hata döndürdüyse (örn: resim çok bulanık)
        setState(() {//neden set state içinde yazdık: yazı değişkene atandığı anda flutter ekranı güncellendsin ve yazıyı ekrana çizsin
          _extractedText = "Hata oluştu: ${result['ErrorMessage']}";
        });
      }
    } catch (e) {
      // İnternet kopması gibi sistemsel bir hata olursa
      setState(() {
        _extractedText = "Bağlantı veya çeviri hatası: $e";
      });
    } finally {
      // İşlem ister başarılı olsun ister hatalı, yükleme durumunu bitir
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Cihazdan resim seçme fonksiyonu
  Future<void> _pickImage() async { //neden async ve Future : galeriye gitmek kullanıcının klasörlerler arasında gezinme tıklama zaman alır jsteki promise ile mantığı aynı
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery); // kulllancı galeriden ImageSource.gallery bir resim seçene kadar veya iptal edip çıkaan kaar bu satırda bekle diyor işlem bitince de seçilen dosyayı image adında geçici değişkene ata
    if (image != null) {
      setState(() {
        _selectedImage = image;
      });
      //neden set state içine yazıldı? set state olmasaydı  arka planda veri gümcellenirdi amam ekrandaki görüntü değişmezdi heniz resim seçilmedi yazısı kalmaya devam ederdi biz bunu state içine yazarak flutter motoruna şunu düyoruz hey flutter benim _selectedImage değişkenimin değeri değişti Lütfen bu sayfayı yeni verilerle baştan aşağı tekrar çiz bu sayede boş gri alan gidiyor benim seçtiğim resim geliyor
    }
  }

  @override // _HomePAgeState classı flutterın kendi içinde olan State adındaki çok geniş ve temel bi sınıftan türetildi  yani flutterın orjinal State sınfıı içinde zaten boş bir buil fonk vardı ancak orj fonk ekrana bir şey çizemez boş durur override yazarak derleyeciye ben onun üstüne yazıyorum diyorum 
  Widget build(BuildContext context) { //flutterda yer kaplayan her şey widget, build metodu flutter motoruna bu sayfa ekranda nasıl gözükecek bana widger haritası ver der ve içine yazılan her şey ekrana çizilir
    return Scaffold( //Scaffold(...) iskele demektir, mobil veya web uygulamasında boş sayfa açıyor sayfa üstünde bi nav bar yani header ortasında body vs vs gelir Scaffold standart layout hazır olarak veren aan şablon htmldeki <body> gibi düşün
      appBar: AppBar(
        title: const Text( //üst barın içine yazılancak metni belirler
        //Text widgeti flutterda ekrana yazı yazdırmanın tek yolu
          'library to excel',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true, //andoidde başlıklar varsayılan sola dayali iosta da ortadadır tru diyerek her platformda ortada durduruyoruz
        backgroundColor: Colors.purple, //üst bar arka plan rengi
        foregroundColor: Colors.white, //üstündeki yazı ve ikonların rengini beyaz yapar
      ),
      body: Center(//dikey ve yatayda centerlıyor
        child: SingleChildScrollView(
          child: Column( //child bunun içine tek bir eleman koyacağım demek children ise buunun içine birden fazla eleman koyacağım(liste şeklinde) demek
        //Column ise içindeki elemanları yukarıdan aşağıya doğru alt alta dizdirir
          mainAxisAlignment: MainAxisAlignment.center, //Colum içindeki elemanarın yukarıya aşağıya yapıştırtmaz
          children: [
            // Resmin gösterileceği alan
            Container( //htmldeki div karşılığı içine başka şeyler koyabildiğin genişlik yükseklik rengini ayarlayabildiğin boş kutu, biz bunu çerçeve olarak kullanıyoruz
              width: 300, //kutu boyutları sabit
              height: 300,
              decoration: BoxDecoration( //makyaj css kısmı burası
                color: Colors.grey[200], //kutu arka plan rengi 200 açıklık koyuluk berlirtir
                border: Border.all(color: Colors.grey.shade400, width: 2), //çerçeve
                borderRadius: BorderRadius.circular(16), //yuvarlatma 16 pixel çapında yuvarlatır 
              ),
              child: _selectedImage == null
                  ? const Column( //const Column(...) içndekileri alt alta diziyor
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.image, size: 50, color: Colors.grey),
                        //flutterın kendi kütüpünden hazır resim ikonu çağır
                        SizedBox(height: 10), //html cssteki margin veya boş bir div yani ikon ve yazı arası 10 pixel dikey boşluk 
                        Text('Henüz bir resim seçilmedi', style: TextStyle(color: Colors.grey)),
                      ],
                    )
                  //iki nokta sonrasında ekran güncellenecek setstate çalışır 
                  : ClipRRect( //cssteki overflow:hidden, yani içine konulan resmi belirttiğimiz yarıçapta krıpar neden 14 çünkü dış kutu  yuvarlaklık 16 2 pixel kenarlık içeriye 14 kalıyor 
                      borderRadius: BorderRadius.circular(14),
                      // Web ve Mobil için farklı resim gösterme metodları
                      child: kIsWeb //webte mi çalışıyor
                          ? Image.network(_selectedImage!.path, fit: BoxFit.cover) //urlden çekeriz
                          //! dartta null assertion yani boş olmama garantisi sisteme diyoruz ki biliyorum bu değişken başta null olabilirdi ama ben üstte kontrol ettim şuan kesinlikle içi dolu bana güven ve pathi al
                          //fit: BoxFit.cover seçilen resim dikdörtgen bile olsa bizim 300*300 kare kutunun en boyunu bozmadan kutuyu tamamen kaplayacak kendini sığdırır fazlalıklar dışarda bırakılır
                          : Image.file(File(_selectedImage!.path), fit: BoxFit.cover), //gerçek dosya yolundan geliyorsa image.file ile çekilir
                    ),
            ),
            const SizedBox(height: 30),//container ile buton yapışmasın diye 30 pixelli görünmez kutu 
            // Resim seçme butonu
            ElevatedButton.icon(
              onPressed: _pickImage, //eğer biz _pickImage() deseydij sayfa açılır açılmaz o fonk kendi kendine çalışır galeriyi açardı biz ise butona basılınca açılsın istiyoruz o yüzden fonksiyonun referansını verdik 
              icon: const Icon(Icons.upload_file), //butonun solundaki ikon flutuer içi hazır ikon çok
              label: const Text(
                'Cihazdan Resim Seç',//buton üzerindeki ana metin, .icon türündeki butonlarda metin kısmı child yerine label adını alır
                style: TextStyle(fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), //iç boşluk
                elevation: 2, //butonun arka plandan ne kadar havada duracağını yani alttaki gölge (box.shadow) derinliğini belirler
              ),
            ),
            const SizedBox(height: 20),
            
            // Eğer resim seçilmişse "Yazıları Oku" butonunu göster
            if (_selectedImage != null)
              _isLoading
                  ? const CircularProgressIndicator() // İnternetteyken dönen çark 
                  : ElevatedButton.icon(
                      onPressed: _extractTextFromImage, //üstüne basılınca bu fonksiyonu yaz 
                      icon: const Icon(Icons.document_scanner),
                      label: const Text(
                        'Resimdeki Yazıları Oku',
                        style: TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange, // Farklı bir renk
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                    ),

            const SizedBox(height: 20),

            // Eğer API'den yazı geldiyse onu gösteren yeşil kutu
            if (_extractedText != null)
              Container(
                width: 1000,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  border: Border.all(color: Colors.green.shade400, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Okunan Metin:',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _extractedText!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
          ],
        ),
        ),
      ),
    );
  }
}