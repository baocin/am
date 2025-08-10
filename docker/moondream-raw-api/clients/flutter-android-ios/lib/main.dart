import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MoondreamApp());
}

class MoondreamApp extends StatelessWidget {
  const MoondreamApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Moondream Vision',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;
  String _apiEndpoint = 'http://localhost:8001';
  String _mode = 'caption';
  String _result = '';
  bool _isLoading = false;
  final TextEditingController _questionController = TextEditingController();
  final TextEditingController _objectController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiEndpoint = prefs.getString('api_endpoint') ?? 'http://localhost:8001';
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_endpoint', _apiEndpoint);
  }

  Future<void> _pickImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source);
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
        _result = '';
      });
    }
  }

  Future<void> _processImage() async {
    if (_selectedImage == null) return;

    setState(() {
      _isLoading = true;
      _result = '';
    });

    try {
      // Convert image to base64
      final bytes = await _selectedImage!.readAsBytes();
      final base64Image = base64Encode(bytes);

      // Prepare API request
      String endpoint = '$_apiEndpoint/';
      Map<String, dynamic> body = {
        'image': 'data:image/jpeg;base64,$base64Image',
      };

      switch (_mode) {
        case 'caption':
          endpoint += 'caption';
          break;
        case 'query':
          endpoint += 'query';
          body['question'] = _questionController.text.isEmpty 
              ? 'What is in this image?' 
              : _questionController.text;
          break;
        case 'detect':
          endpoint += 'detect';
          body['object'] = _objectController.text.isEmpty 
              ? 'person' 
              : _objectController.text;
          break;
        case 'point':
          endpoint += 'point';
          body['object'] = _objectController.text.isEmpty 
              ? 'person' 
              : _objectController.text;
          break;
      }

      // Send request
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _result = _formatResult(data);
        });
      } else {
        setState(() {
          _result = 'Error: ${response.statusCode} - ${response.body}';
        });
      }
    } catch (e) {
      setState(() {
        _result = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _formatResult(Map<String, dynamic> data) {
    switch (_mode) {
      case 'caption':
        return data['caption'] ?? 'No caption generated';
      case 'query':
        return data['answer'] ?? 'No answer generated';
      case 'detect':
        final detections = data['detections'] as List?;
        if (detections == null || detections.isEmpty) {
          return 'No objects detected';
        }
        return 'Detected ${detections.length} object(s):\n' +
            detections.map((d) => '• ${d.toString()}').join('\n');
      case 'point':
        final coords = data['coordinates'];
        if (coords == null) return 'No coordinates found';
        return 'Coordinates: ${coords.toString()}';
      default:
        return data.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Moondream Vision'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettings,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Mode Selection
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Analysis Mode',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'caption', label: Text('Caption')),
                        ButtonSegment(value: 'query', label: Text('Query')),
                        ButtonSegment(value: 'detect', label: Text('Detect')),
                        ButtonSegment(value: 'point', label: Text('Point')),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (Set<String> newSelection) {
                        setState(() {
                          _mode = newSelection.first;
                        });
                      },
                    ),
                    if (_mode == 'query') ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: _questionController,
                        decoration: const InputDecoration(
                          labelText: 'Question',
                          hintText: 'What would you like to know about the image?',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    if (_mode == 'detect' || _mode == 'point') ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: _objectController,
                        decoration: const InputDecoration(
                          labelText: 'Object to find',
                          hintText: 'e.g., person, car, dog',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Image Display
            Card(
              child: _selectedImage == null
                  ? Container(
                      height: 300,
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.image_outlined,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No image selected',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        _selectedImage!,
                        height: 300,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
            ),
            const SizedBox(height: 16),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _selectedImage == null || _isLoading ? null : _processImage,
              icon: _isLoading 
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.analytics),
              label: Text(_isLoading ? 'Processing...' : 'Analyze Image'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
            const SizedBox(height: 16),

            // Results
            if (_result.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Results',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        _result,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Settings'),
        content: TextField(
          decoration: const InputDecoration(
            labelText: 'API Endpoint',
            hintText: 'http://localhost:8001',
          ),
          controller: TextEditingController(text: _apiEndpoint),
          onChanged: (value) {
            _apiEndpoint = value;
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _saveSettings();
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}