// main.dart
// Helpo Services - Flutter single-file example
// NOTE: This is a single-file starter. For production split into multiple files.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(HelpoApp());
}

const String API_BASE = 'http://YOUR_SERVER_IP:5000'; // <-- change to your Flask server

class HelpoApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Helpo Services',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
      ),
      home: HomeScreen(),
      routes: {
        '/register': (_) => VendorRegisterScreen(),
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  TextEditingController qCtrl = TextEditingController();
  TextEditingController locCtrl = TextEditingController();
  List vendors = [];
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _fetchVendors();
  }

  Future<void> _fetchVendors({String q = '', String loc = ''}) async {
    setState(() => loading = true);
    try {
      final uri = Uri.parse('$API_BASE/api/vendors').replace(queryParameters: {
        if (q.isNotEmpty) 'query': q,
        if (loc.isNotEmpty) 'location': loc,
      });
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        setState(() {
          vendors = json.decode(res.body) as List;
        });
      } else {
        print('Failed to load vendors: ${res.statusCode}');
      }
    } catch (e) {
      print('Error fetching vendors: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  void _search() => _fetchVendors(q: qCtrl.text.trim(), loc: locCtrl.text.trim());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Helpo Services'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/register'),
            icon: Icon(Icons.add_business, color: Colors.white),
            label: Text('Register', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: qCtrl,
                    decoration: InputDecoration(hintText: 'Search service or business'),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: locCtrl,
                    decoration: InputDecoration(hintText: 'City or area'),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                IconButton(onPressed: _search, icon: Icon(Icons.search))
              ],
            ),
            SizedBox(height: 12),
            Expanded(
              child: loading
                  ? Center(child: CircularProgressIndicator())
                  : vendors.isEmpty
                      ? Center(child: Text('No vendors found'))
                      : ListView.builder(
                          itemCount: vendors.length,
                          itemBuilder: (_, i) => VendorCard(vendor: vendors[i]),
                        ),
            )
          ],
        ),
      ),
    );
  }
}

class VendorCard extends StatelessWidget {
  final Map vendor;
  VendorCard({required this.vendor});

  @override
  Widget build(BuildContext context) {
    final phone = (vendor['phone'] ?? '').toString();
    final photos = (vendor['photos'] ?? '').toString().split(',').where((s) => s.trim().isNotEmpty).toList();
    final thumbnail = photos.isNotEmpty ? photos.first : null;

    return Card(
      margin: EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        leading: thumbnail != null
            ? Image.network('$API_BASE/static/uploads/$thumbnail', width: 72, height: 72, fit: BoxFit.cover)
            : Container(width: 72, height: 72, color: Colors.grey[200], child: Icon(Icons.store)),
        title: Text(vendor['business_name'] ?? 'Unnamed'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(vendor['category'] ?? ''),
            SizedBox(height: 4),
            Text('${vendor['city'] ?? ''}'),
          ],
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'call') {
              final uri = Uri.parse('tel:+91$phone');
              if (await canLaunchUrl(uri)) launchUrl(uri);
            } else if (v == 'whatsapp') {
              final wa = Uri.parse('https://wa.me/91$phone?text=${Uri.encodeComponent('Hi, I found you on Helpo Services.')}');
              if (await canLaunchUrl(wa)) launchUrl(wa);
            } else if (v == 'detail') {
              Navigator.push(context, MaterialPageRoute(builder: (_) => VendorDetailScreen(phone: phone)));
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'call', child: Text('Call')),
            PopupMenuItem(value: 'whatsapp', child: Text('WhatsApp')),
            PopupMenuItem(value: 'detail', child: Text('View')),
          ],
        ),
      ),
    );
  }
}

class VendorDetailScreen extends StatefulWidget {
  final String phone;
  VendorDetailScreen({required this.phone});
  @override
  _VendorDetailScreenState createState() => _VendorDetailScreenState();
}

class _VendorDetailScreenState extends State<VendorDetailScreen> {
  Map vendor = {};
  List reviews = [];
  bool loading = false;

  final _nameCtrl = TextEditingController();
  int _rating = 5;
  final _commentCtrl = TextEditingController();
  XFile? _pickedPhoto;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final uri = Uri.parse('$API_BASE/vendor/${widget.phone}');
      // The Flask route /vendor/<phone> returns HTML. We'll call the API counterpart if available (/api/vendors) to fetch single vendor.
      // Here we call /api/vendors then find the phone entry.
      final res = await http.get(Uri.parse('$API_BASE/api/vendors'));
      if (res.statusCode == 200) {
        final list = json.decode(res.body) as List;
        vendor = list.cast<Map>().firstWhere((v) => v['phone'].toString().trim() == widget.phone.trim(), orElse: () => {});
      }
      // For reviews, call a simple endpoint if exists. If not, vendor object may include review_count only.
      // If you have a dedicated GET reviews API, replace below.
      // Fallback: show empty reviews.
    } catch (e) {
      print('Error loading vendor detail: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _submitReview() async {
    final uri = Uri.parse('$API_BASE/vendor/${widget.phone}'); // this expects multipart POST
    final request = http.MultipartRequest('POST', uri);
    request.fields['name'] = _nameCtrl.text.trim();
    request.fields['rating'] = _rating.toString();
    request.fields['comment'] = _commentCtrl.text.trim();
    if (_pickedPhoto != null) {
      request.files.add(await http.MultipartFile.fromPath('review_photo', _pickedPhoto!.path));
    }

    final streamed = await request.send();
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Review submitted')));
      _nameCtrl.clear();
      _commentCtrl.clear();
      _pickedPhoto = null;
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to submit review')));
    }
  }

  Future<void> _pickPhoto() async {
    final p = ImagePicker();
    final picked = await p.pickImage(source: ImageSource.gallery, maxWidth: 1200);
    if (picked != null) setState(() => _pickedPhoto = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(vendor['business_name'] ?? 'Vendor')),
      body: loading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((vendor['photos'] ?? '').toString().isNotEmpty)
                    SizedBox(
                      height: 140,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: vendor['photos']
                                .toString()
                                .split(',')
                                .where((s) => s.trim().isNotEmpty)
                                .map<Widget>((p) => Padding(
                                      padding: const EdgeInsets.only(right: 8.0),
                                      child: Image.network('$API_BASE/static/uploads/${p.trim()}', height: 120),
                                    ))
                                .toList() as List<Widget>?,
                      ),
                    ),
                  SizedBox(height: 12),
                  Text(vendor['business_name'] ?? '', style: Theme.of(context).textTheme.headline6),
                  SizedBox(height: 4),
                  Text(vendor['category'] ?? ''),
                  SizedBox(height: 8),
                  Text(vendor['description'] ?? ''),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      ElevatedButton.icon(
                          onPressed: () async {
                            final phone = vendor['phone'];
                            final uri = Uri.parse('tel:+91${phone}');
                            if (await canLaunchUrl(uri)) launchUrl(uri);
                          },
                          icon: Icon(Icons.call),
                          label: Text('Call')),
                      SizedBox(width: 8),
                      ElevatedButton.icon(
                          onPressed: () async {
                            final phone = vendor['phone'];
                            final wa = Uri.parse('https://wa.me/91${phone}?text=${Uri.encodeComponent('Hi, I found you on Helpo Services.')}');
                            if (await canLaunchUrl(wa)) launchUrl(wa);
                          },
                          icon: Icon(Icons.chat),
                          label: Text('WhatsApp')),
                    ],
                  ),

                  Divider(height: 24),

                  Text('Submit a review', style: Theme.of(context).textTheme.subtitle1),
                  SizedBox(height: 8),
                  TextField(controller: _nameCtrl, decoration: InputDecoration(labelText: 'Your name')),
                  SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: _rating,
                    items: List.generate(5, (i) => i + 1)
                        .map((v) => DropdownMenuItem(value: v, child: Text('$v Star${v > 1 ? 's' : ''}')))
                        .toList(),
                    onChanged: (v) => setState(() => _rating = v ?? 5),
                    decoration: InputDecoration(labelText: 'Rating'),
                  ),
                  SizedBox(height: 8),
                  TextField(controller: _commentCtrl, decoration: InputDecoration(labelText: 'Comment'), maxLines: 3),
                  SizedBox(height: 8),
                  Row(children: [
                    ElevatedButton.icon(onPressed: _pickPhoto, icon: Icon(Icons.photo), label: Text('Pick Photo')),
                    SizedBox(width: 8),
                    if (_pickedPhoto != null) Text('Picked')
                  ]),
                  SizedBox(height: 12),
                  ElevatedButton(onPressed: _submitReview, child: Text('Submit Review')),
                ],
              ),
            ),
    );
  }
}

class VendorRegisterScreen extends StatefulWidget {
  @override
  _VendorRegisterScreenState createState() => _VendorRegisterScreenState();
}

class _VendorRegisterScreenState extends State<VendorRegisterScreen> {
  int _page = 1;
  final _formKey = GlobalKey<FormState>();

  // Page 1
  final _businessCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool emailVerified = false;

  // Page 2
  final _plotCtrl = TextEditingController();
  final _buildingCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _landmarkCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _pincodeCtrl = TextEditingController();

  // Page 3
  final _categoryCtrl = TextEditingController();
  final _serviceHoursCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  List<XFile> _photos = [];

  final ImagePicker _picker = ImagePicker();

  Future<void> _sendEmailOtp() async {
    final res = await http.post(Uri.parse('$API_BASE/send_email_otp'), body: {'email': _emailCtrl.text.trim()});
    final j = json.decode(res.body);
    if (j['status'] == 'success') ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Email OTP sent')));
    else ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to send OTP')));
  }

  Future<void> _verifyEmailOtp(String otp) async {
    final res = await http.post(Uri.parse('$API_BASE/verify_email_otp'), body: {'email': _emailCtrl.text.trim(), 'otp': otp});
    final j = json.decode(res.body);
    if (j['status'] == 'success') {
      setState(() => emailVerified = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Email verified')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('OTP incorrect')));
    }
  }

  Future<void> _pickPhotos() async {
    final picked = await _picker.pickMultiImage(imageQuality: 80);
    if (picked != null) setState(() => _photos = picked);
  }

  void _next() {
    if (_page == 1) {
      if (_businessCtrl.text.trim().isEmpty || !RegExp(r'^[6-9]\d{9}\$').hasMatch(_phoneCtrl.text.trim())) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Please complete required fields')));
        return;
      }
      if (_passCtrl.text != _confirmCtrl.text || _passCtrl.text.length < 8) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Password validation failed')));
        return;
      }
      if (!emailVerified) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Please verify email OTP')));
        return;
      }
    }

    setState(() => _page = (_page + 1).clamp(1, 3));
  }

  void _prev() => setState(() => _page = (_page - 1).clamp(1, 3));

  Future<void> _submit() async {
    final uri = Uri.parse('$API_BASE/vendor');
    final req = http.MultipartRequest('POST', uri);
    req.fields.addAll({
      'business_name': _businessCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'password': _passCtrl.text,
      'confirm_password': _confirmCtrl.text,
      'plot_info': _plotCtrl.text,
      'building_info': _buildingCtrl.text,
      'street': _streetCtrl.text,
      'landmark': _landmarkCtrl.text,
      'area': _areaCtrl.text,
      'city': _cityCtrl.text,
      'state': _stateCtrl.text,
      'pincode': _pincodeCtrl.text,
      'category': _categoryCtrl.text,
      'service_hours': _serviceHoursCtrl.text,
      'description': _descCtrl.text,
    });

    for (var p in _photos) {
      req.files.add(await http.MultipartFile.fromPath('photos', p.path));
    }

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode == 200) {
      final body = resp.body;
      // The server returns HTML; check message in body or redirect. We'll show success and pop.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Registered (check server response)')));
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Registration failed')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Register Your Business')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(12),
        child: Column(
          children: [
            StepperHeader(page: _page),
            if (_page == 1) _buildPage1(),
            if (_page == 2) _buildPage2(),
            if (_page == 3) _buildPage3(),
            SizedBox(height: 12),
            Row(
              children: [
                if (_page > 1) ElevatedButton(onPressed: _prev, child: Text('Back')),
                Spacer(),
                if (_page < 3) ElevatedButton(onPressed: _next, child: Text('Next')),
                if (_page == 3) ElevatedButton(onPressed: _submit, child: Text('Register')),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildPage1() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(controller: _businessCtrl, decoration: InputDecoration(labelText: 'Business Name')),
          TextFormField(controller: _phoneCtrl, decoration: InputDecoration(labelText: 'Phone')),
          TextFormField(controller: _emailCtrl, decoration: InputDecoration(labelText: 'Email')),
          SizedBox(height: 8),
          Row(children: [
            ElevatedButton(onPressed: _sendEmailOtp, child: Text('Send Email OTP')),
            SizedBox(width: 8),
            ElevatedButton(onPressed: () async {
              final otp = await _showOtpDialog();
              if (otp != null) _verifyEmailOtp(otp);
            }, child: Text('Verify OTP')),
          ]),
          SizedBox(height: 8),
          TextFormField(controller: _passCtrl, decoration: InputDecoration(labelText: 'Password'), obscureText: true),
          TextFormField(controller: _confirmCtrl, decoration: InputDecoration(labelText: 'Confirm Password'), obscureText: true),
        ],
      ),
    );
  }

  Widget _buildPage2() {
    return Column(
      children: [
        TextFormField(controller: _plotCtrl, decoration: InputDecoration(labelText: 'Plot / Bldg / Shop / Floor')),
        TextFormField(controller: _buildingCtrl, decoration: InputDecoration(labelText: 'Building / Market / Colony')),
        TextFormField(controller: _streetCtrl, decoration: InputDecoration(labelText: 'Street / Road')),
        TextFormField(controller: _landmarkCtrl, decoration: InputDecoration(labelText: 'Landmark')),
        TextFormField(controller: _areaCtrl, decoration: InputDecoration(labelText: 'Area')),
        TextFormField(controller: _cityCtrl, decoration: InputDecoration(labelText: 'City')),
        TextFormField(controller: _stateCtrl, decoration: InputDecoration(labelText: 'State')),
        TextFormField(controller: _pincodeCtrl, decoration: InputDecoration(labelText: 'Pincode')),
      ],
    );
  }

  Widget _buildPage3() {
    return Column(
      children: [
        TextFormField(controller: _categoryCtrl, decoration: InputDecoration(labelText: 'Business Category')),
        TextFormField(controller: _serviceHoursCtrl, decoration: InputDecoration(labelText: 'Service Hours')),
        SizedBox(height: 8),
        ElevatedButton(onPressed: _pickPhotos, child: Text('Pick Photos')),
        SizedBox(height: 8),
        if (_photos.isNotEmpty)
          Wrap(children: _photos.map((p) => Padding(padding: EdgeInsets.all(4), child: Image.file(File(p.path), width: 80, height: 80, fit: BoxFit.cover))).toList()),
        TextFormField(controller: _descCtrl, decoration: InputDecoration(labelText: 'Business Description'), maxLines: 3),
      ],
    );
  }

  Future<String?> _showOtpDialog() async {
    final ctrl = TextEditingController();
    return showDialog<String>(context: context, builder: (ctx) {
      return AlertDialog(
        title: Text('Enter OTP'),
        content: TextField(controller: ctrl, keyboardType: TextInputType.number, decoration: InputDecoration(hintText: '6-digit OTP')),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text('Verify'))],
      );
    });
  }
}

class StepperHeader extends StatelessWidget {
  final int page;
  StepperHeader({required this.page});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _dot(1), Expanded(child: Divider()), _dot(2), Expanded(child: Divider()), _dot(3)
      ],
    );
  }

  Widget _dot(int n) => CircleAvatar(radius: 12, backgroundColor: n <= page ? Colors.deepPurple : Colors.grey, child: Text('$n', style: TextStyle(color: Colors.white)));
}
