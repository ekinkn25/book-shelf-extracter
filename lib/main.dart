import 'dart:convert';
import 'dart:typed_data';

// dart:io YOK — web'de patlıyordu, tamamen kaldırıldı.
// Resim gösterimi için Image.memory + readAsBytes() kullanıyoruz.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:excel/excel.dart' as xl;
import 'package:universal_html/html.dart' as html;

// ─────────────────────────────────────────────
// Kitap modeli: Gemini'den ve Google Books'tan
// gelen veriyi bir arada tutmak için.
// ─────────────────────────────────────────────
class BookResult {
  final String rawTitle;       // Gemini'nin okuduğu ham isim
  final String? confirmedTitle; // Google Books'un onayladığı resmi ad
  final String? author;         // Google Books'tan gelen yazar
  final bool found;             // Google Books'ta bulundu mu?

  BookResult({
    required this.rawTitle,
    this.confirmedTitle,
    this.author,
    required this.found,
  });
}

// ─────────────────────────────────────────────
// main: dotenv yükle, uygulamayı başlat
// ─────────────────────────────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Library to Excel',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      home: const HomePage(),
    );
  }
}

// ─────────────────────────────────────────────
// Ana sayfa state'i
// ─────────────────────────────────────────────
class _HomePageState extends State<HomePage> {
  XFile? _selectedImage;
  Uint8List? _imageBytes; // dart:io'suz resim gösterimi için
  final ImagePicker _picker = ImagePicker();

  List<BookResult> _bookResults = [];
  bool _isLoading = false;
  String _statusMessage = '';

  // ── 1. Resim seç ──────────────────────────────
  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    // readAsBytes() hem web'de hem mobilde çalışır; File() gerektirmez.
    final bytes = await image.readAsBytes();

    setState(() {
      _selectedImage = image;
      _imageBytes = bytes;
      _bookResults = [];
      _statusMessage = '';
    });
  }

  // ── 2. Ana işlem: Gemini → Google Books ───────
  Future<void> _processImage() async {
    if (_selectedImage == null || _imageBytes == null) return;

    setState(() {
      _isLoading = true;
      _bookResults = [];
      _statusMessage = 'Gemini resmi analiz ediyor...';
    });

    try {
      // ── 2a. API anahtarını al ──
      final geminiKey = dotenv.env['GEMINI_API_KEY'];
      if (geminiKey == null || geminiKey.isEmpty) {
        _showError('.env dosyasında GEMINI_API_KEY bulunamadı!');
        return;
      }

      // ── 2b. Gemini modeli ──
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: geminiKey,
      );

      final mimeType = _selectedImage!.name.toLowerCase().endsWith('.png')
          ? 'image/png'
          : 'image/jpeg';

      final imagePart = DataPart(mimeType, _imageBytes!);

      // ── 2c. Prompt: sadece "Kitap Adı - Yazar" listesi iste ──
      // Her satır ayrı bir kitap olacak şekilde kesin format belirtiyoruz.
      // Bu sayede parse etmek kolaylaşır.
      final prompt = TextPart(
        "Bu resimde bir kitaplık var. Görünen kitapların isimlerini ve yazarlarını tespit et.\n"
        "KURALLAR:\n"
        "- Her kitabı yeni satıra yaz.\n"
        "- Format kesinlikle şu şekilde olmalı: Kitap Adı | Yazar\n"
        "- Yazar bilinmiyorsa: Kitap Adı | Bilinmiyor\n"
        "- ISBN, barkod, yayınevi logosu, anlamsız harf/sayı kombinasyonlarını yoksay.\n"
        "- Sadece kitap isim-yazar listesini yaz, başka hiçbir şey yazma.\n"
        "- Açıklama, giriş cümlesi, numara ekleme.",
      );

      final response = await model.generateContent([
        Content.multi([prompt, imagePart])
      ]);

      final rawText = response.text ?? '';
      if (rawText.isEmpty) {
        _showError('Gemini resimden metin çıkaramadı.');
        return;
      }

      // ── 2d. Gemini çıktısını parse et ──
      final lines = rawText
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && l.contains('|'))
          .toList();

      if (lines.isEmpty) {
        _showError('Resimde okunabilir kitap bulunamadı.');
        return;
      }

      // ── 2e. Her kitap için Google Books'ta doğrula ──
      setState(() => _statusMessage =
          'Google Books ile doğrulanıyor (${lines.length} kitap)...');

      final results = <BookResult>[];
      for (final line in lines) {
        final parts = line.split('|');
        final rawTitle = parts[0].trim();
        final rawAuthor = parts.length > 1 ? parts[1].trim() : '';

        final bookResult = await _searchGoogleBooks(rawTitle, rawAuthor);
        results.add(bookResult);

        // Her sonuç geldiğinde ekranı güncelle (anlık geri bildirim)
        setState(() {
          _bookResults = List.from(results);
          _statusMessage =
              'Doğrulanıyor: ${results.length}/${lines.length}';
        });
      }

      setState(() {
        _bookResults = results;
        _statusMessage =
            '${results.where((r) => r.found).length}/${results.length} kitap doğrulandı.';
      });
    } catch (e) {
      _showError('Hata oluştu: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── 3. Google Books API sorgusu ───────────────
  Future<BookResult> _searchGoogleBooks(
      String title, String author) async {
    // Sorgu: başlık + varsa yazar kombinasyonu
    final booksKey = dotenv.env['BOOKS_API_KEY'] ?? '';

    final query = author.isNotEmpty && author != 'Bilinmiyor'
        ? Uri.encodeComponent('intitle:$title inauthor:$author')
        : Uri.encodeComponent('intitle:$title');

    final url =
        'https://www.googleapis.com/books/v1/volumes?q=$query&maxResults=1&printType=books&key=$booksKey';

    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        return BookResult(rawTitle: title, found: false);
      }

      final data = jsonDecode(response.body);
      final items = data['items'] as List?;

      if (items == null || items.isEmpty) {
        return BookResult(rawTitle: title, found: false);
      }

      final volumeInfo = items[0]['volumeInfo'] as Map<String, dynamic>;
      final confirmedTitle = volumeInfo['title'] as String?;
      final authors = volumeInfo['authors'] as List?;
      final confirmedAuthor =
          authors != null ? authors.join(', ') : 'Bilinmiyor';

      return BookResult(
        rawTitle: title,
        confirmedTitle: confirmedTitle,
        author: confirmedAuthor,
        found: true,
      );
    } catch (_) {
      // Timeout veya ağ hatası: bulunamadı olarak işaretle
      return BookResult(rawTitle: title, found: false);
    }
  }

  // ── 4. Excel oluştur ve indir ─────────────────
  Future<void> _exportToExcel() async {
    if (_bookResults.isEmpty) return;

    final excel = xl.Excel.createExcel();
    final sheet = excel['Kitaplarım'];

    // Başlık satırı
    sheet.appendRow([
      xl.TextCellValue('Ham Başlık (Fotoğraftan)'),
      xl.TextCellValue('Doğrulanmış Başlık'),
      xl.TextCellValue('Yazar'),
      xl.TextCellValue('Durum'),
    ]);

    // Stil: başlık satırını kalın yap
    for (int col = 0; col < 4; col++) {
      final cell = sheet.cell(
        xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0),
      );
      cell.cellStyle = xl.CellStyle(bold: true);
    }

    // Veri satırları
    for (final book in _bookResults) {
      sheet.appendRow([
        xl.TextCellValue(book.rawTitle),
        xl.TextCellValue(book.confirmedTitle ?? '-'),
        xl.TextCellValue(book.author ?? '-'),
        xl.TextCellValue(book.found ? '✓ Doğrulandı' : '✗ Bulunamadı'),
      ]);
    }

    // Sütun genişlikleri
    sheet.setColumnWidth(0, 35);
    sheet.setColumnWidth(1, 35);
    sheet.setColumnWidth(2, 25);
    sheet.setColumnWidth(3, 15);

    // Varsayılan boş sayfayı sil
    excel.delete('Sheet1');

    final bytes = excel.encode();
    if (bytes == null) return;

    if (kIsWeb) {
      // Web: Blob + anchor trick ile indir
      final blob = html.Blob([Uint8List.fromList(bytes)],
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', 'kitaplarim.xlsx')
        ..click();
      html.Url.revokeObjectUrl(url);
    } else {
      // Mobil: Basit bildirim — dosya kaydetme için path_provider eklenebilir
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Mobil kaydetme için path_provider entegrasyonu gerekli.')),
        );
      }
    }
  }

  void _showError(String message) {
    setState(() {
      _statusMessage = message;
      _isLoading = false;
    });
  }

  // ── UI ───────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          '📚 Library to Excel',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        centerTitle: true,
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        elevation: 0,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Resim kutusu ──
                _buildImageBox(colorScheme),
                const SizedBox(height: 24),

                // ── Butonlar ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _isLoading ? null : _pickImage,
                      icon: const Icon(Icons.upload_file_rounded),
                      label: const Text('Fotoğraf Seç'),
                    ),
                    const SizedBox(width: 16),
                    if (_selectedImage != null)
                      FilledButton.icon(
                        onPressed: _isLoading ? null : _processImage,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.auto_fix_high_rounded),
                        label: Text(_isLoading ? 'İşleniyor...' : 'Analiz Et'),
                        style: FilledButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                        ),
                      ),
                  ],
                ),

                // ── Durum mesajı ──
                if (_statusMessage.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _statusMessage.startsWith('Hata')
                          ? colorScheme.error
                          : colorScheme.secondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],

                // ── Sonuç tablosu ──
                if (_bookResults.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  _buildResultTable(colorScheme),
                  const SizedBox(height: 16),
                  Center(
                    child: FilledButton.icon(
                      onPressed: _exportToExcel,
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Excel Olarak İndir'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageBox(ColorScheme colorScheme) {
    return Container(
      height: 280,
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant,
          width: 2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: _imageBytes == null
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.photo_library_outlined,
                    size: 56, color: colorScheme.outline),
                const SizedBox(height: 12),
                Text(
                  'Kitaplığın fotoğrafını seç',
                  style: TextStyle(color: colorScheme.outline, fontSize: 16),
                ),
              ],
            )
          // Image.memory: dart:io gerektirmez, web + mobil çalışır
          : Image.memory(_imageBytes!, fit: BoxFit.cover, width: double.infinity),
    );
  }

  Widget _buildResultTable(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bulunan Kitaplar (${_bookResults.length})',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Table(
            columnWidths: const {
              0: FlexColumnWidth(3),
              1: FlexColumnWidth(2),
              2: FixedColumnWidth(90),
            },
            children: [
              // Başlık satırı
              TableRow(
                decoration:
                    BoxDecoration(color: colorScheme.primaryContainer),
                children: [
                  _tableHeader('Kitap Adı'),
                  _tableHeader('Yazar'),
                  _tableHeader('Durum'),
                ],
              ),
              // Veri satırları
              ..._bookResults.asMap().entries.map((entry) {
                final index = entry.key;
                final book = entry.value;
                final isEven = index % 2 == 0;
                return TableRow(
                  decoration: BoxDecoration(
                    color: isEven
                        ? colorScheme.surface
                        : colorScheme.surfaceVariant.withOpacity(0.4),
                  ),
                  children: [
                    _tableCell(
                        book.confirmedTitle ?? book.rawTitle, bold: true),
                    _tableCell(book.author ?? '-'),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 8),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: book.found
                                ? Colors.green.shade100
                                : Colors.red.shade100,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            book.found ? '✓' : '✗',
                            style: TextStyle(
                              color: book.found
                                  ? Colors.green.shade800
                                  : Colors.red.shade800,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tableHeader(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
      );

  Widget _tableCell(String text, {bool bold = false}) => Padding(
        padding:
            const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
            fontSize: 13.5,
          ),
        ),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}