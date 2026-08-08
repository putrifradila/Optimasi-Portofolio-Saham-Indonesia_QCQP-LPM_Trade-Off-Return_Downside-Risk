%% ========================================================================
%  FINAL PROJECT: OPTIMASI PORTOFOLIO QCQP-LPM2 (ITERASI LAMBDA)
%  Objective: Trade-off (Minimize Lambda*Risk - Return)
%  Constraints:
%     1. LPM2 <= R_max (Downside Risk Constraint)
%     2. No Short Selling (Long Only)
%  Output: 
%     1. Tabel Perbandingan Return vs Risk untuk berbagai Lambda
%     2. Grafik Efficient Frontier
%     3. Detail Bobot Saham untuk Lambda terpilih
%  ========================================================================
clear; clc; close all;

%% ---------------------------
%  1. SETTINGS & LOAD DATA
%% ---------------------------
file_path = "C:\Users\KRISNA BAYU\Downloads\Data_SAHAM_MENTAH_LPM2_KAPSEL_MI.xlsx"; 
sheet_name = "Data_Harga"; 

fprintf('Membaca data harga saham...\n');
try
    opts = detectImportOptions(file_path, 'Sheet', sheet_name);
    opts.VariableNamingRule = 'preserve';
    Tbl = readtable(file_path, opts);
    
    raw_prices = Tbl{:, 2:end};          
    stock_names = Tbl.Properties.VariableNames(2:end); 
    
    if any(isnan(raw_prices(:))), error('Data mengandung NaN.'); end
catch ME
    error('Gagal membaca file.\nError: %s', ME.message);
end

%% ---------------------------
%  2. PRE-PROCESSING (Log Return)
%% ---------------------------
log_returns = diff(log(raw_prices)); 
mu = mean(log_returns)'; 
Sigma = cov(log_returns); 

[T, n] = size(log_returns);
fprintf('Data loaded: %d assets, %d observations.\n', n, T);


%  3. PARAMETERS & ITERATION SETUP
%Tau    = mean(mu);  % Target return minimal = Rata-rata pasar
% [TINGGAL UN COMMENT AJA KALAU MAU TAU KEDUA]
Tau    = 0.00;      % Target return minimal
R_max  = 0.1;    % Constraint LPM2 (Risk Limit)

% --- LIST LAMBDA UNTUK ITERASI ---
% 0.1 (Agresif/Risk Taker) ---> 100 (Konservatif/Risk Averse)
lambda_list = [0.1, 0.5, 1, 2, 5, 10, 20, 50, 100, 150, 200, 300, 400, 500, 1000, 1500, 2000, 3000, 5000, 10000]; 
num_iter = length(lambda_list);

% Variabel Penyimpanan Hasil
res_ret  = zeros(num_iter, 1);
res_risk = zeros(num_iter, 1);
res_lpm  = zeros(num_iter, 1);
store_weights = zeros(n, num_iter); % Simpan bobot tiap iterasi

fprintf('\n=== MEMULAI ITERASI LAMBDA (EFFICIENT FRONTIER) ===\n');
fprintf('%-5s | %-10s | %-12s | %-12s | %-10s\n', 'Iter', 'Lambda', 'Return(%)', 'Risk(%)', 'Status');
fprintf('-------------------------------------------------------------\n');

%% ---------------------------
%  4. LOOPING OPTIMIZATION (PURE LPM2 MODEL)
%  Objective: Min (Lambda * LPM2 - Return)
%  Constraint: LPM2 <= R_max
%% ---------------------------
for k = 1:num_iter
    lambda = lambda_list(k);
    
    % --- BUILD PROBLEM ---
    NV = n + T; 
    idx_w = 1:n; idx_pos = n+1:n+T;
    
    % A. OBJECTIVE FUNCTION (MURNI LPM2)
    % Kita ingin minimize: (lambda * LPM2) - Return
    % Rumus LPM2 = (1/T) * sum(pos^2)
    
    % 1. Bagian Linear (c): Maximize Return
    prob.c = zeros(NV,1);
    prob.c(idx_w) = -mu; 
    
    % 2. Bagian Kuadratik (Q): Minimize LPM2
    % Di Mosek: 0.5 x' Q x. Kita butuh: (lambda/T) * pos^2
    % Maka diagonal Q harus diisi: 2 * (lambda/T)
    
    prob.qosubi = idx_pos';      
    prob.qosubj = idx_pos';      
    prob.qoval  = (2 * lambda / T) * ones(T, 1); 
    
    % B. CONSTRAINTS
    A_sum = zeros(1, NV); A_sum(idx_w) = 1;      
    A_pos = [log_returns, eye(T)];               
    
    A_lin = [A_sum; A_pos];
    prob.a = sparse([A_lin; sparse(1, NV)]); % Baris terakhir kosong utk QC
    
    prob.blc = [1; Tau * ones(T, 1); -inf];
    prob.buc = [1; inf(T, 1); T * R_max]; % <--- CONSTRAINT LPM2 DI SINI
    
    % C. BOUNDS
    prob.blx = [zeros(n,1); zeros(T,1)];
    prob.bux = inf(NV,1);
    
    % D. QUADRATIC CONSTRAINT SETUP
    idx_qc = size(prob.a, 1);
    prob.qcsubk = repmat(idx_qc, T, 1);
    prob.qcsubi = idx_pos';
    prob.qcsubj = idx_pos';
    prob.qcval  = 2 * ones(T, 1);
    
    % --- SOLVE ---
    [~, res] = mosekopt('minimize echo(0)', prob); 
    
    % --- SIMPAN HASIL ---
    if isfield(res, 'sol') && strcmp(res.sol.itr.solsta, 'OPTIMAL')
        w_opt = res.sol.itr.xx(idx_w);
        store_weights(:, k) = w_opt;
        res_ret(k)  = mu' * w_opt;
        res_risk(k) = sqrt(w_opt' * Sigma * w_opt); % Std Dev (Hanya info tambahan)
        res_lpm(k)  = mean(max(0, Tau - log_returns*w_opt).^2); % Risk Utama
        stat = 'OPTIMAL';
    else
        stat = 'FAILED';
    end
    
    % Cetak LPM2 di tabel log
    fprintf('%-5d | %-10.1f | %-12.4f | %-12.8f | %s\n', ...
        k, lambda, res_ret(k)*100, res_lpm(k), stat);
end

%% ---------------------------
%  5. VISUALISASI EFFICIENT FRONTIER
%% ---------------------------
figure('Name', 'Efficient Frontier QCQP-LPM2', 'Color', 'w');
plot(res_risk*100, res_ret*100, '-o', 'LineWidth', 2, ...
    'MarkerFaceColor', 'b', 'MarkerSize', 8);
grid on;
title('Efficient Frontier: Trade-off Risk vs Return (LPM2 Constraint)', 'FontSize', 12);
xlabel('Risiko (Standard Deviation) %', 'FontSize', 10);
ylabel('Expected Return (Daily) %', 'FontSize', 10);

% Tambahkan label Lambda pada grafik
for k=1:num_iter
    text(res_risk(k)*100, res_ret(k)*100, sprintf('  \\lambda=%.1f', lambda_list(k)), ...
        'FontSize', 8, 'VerticalAlignment', 'bottom');
end

%% ---------------------------
%  6. DETAIL LAPORAN UNTUK LAMBDA TERPILIH
%  Misal: Kita ingin menampilkan detail untuk Lambda = 1 (Iterasi ke-3)
%  Anda bisa ganti index 'idx_sel' sesuai keinginan
%% ---------------------------
target_lambda = 1.0; 
[~, idx_sel] = min(abs(lambda_list - target_lambda)); % Cari index lambda terdekat

w_final = store_weights(:, idx_sel);

fprintf('\n================================================\n');
fprintf(' DETAIL PORTOFOLIO TERPILIH (Lambda = %.1f) \n', lambda_list(idx_sel));
fprintf('================================================\n');
fprintf('Karakteristik: %.4f%% Return | %.4f%% Risk\n', res_ret(idx_sel)*100, res_risk(idx_sel)*100);
fprintf('------------------------------------------------\n');
fprintf('%-10s : %10s\n', 'Saham', 'Bobot (%)');
fprintf('------------------------------------------------\n');

for i=1:n
    val = w_final(i);
    if abs(val) < 1e-4, val = 0; end
    fprintf('%-10s : %10.4f %%\n', stock_names{i}, val*100);
end
fprintf('------------------------------------------------\n');
fprintf('Total Bobot: %.4f\n', sum(w_final));
fprintf('LPM2 Value : %.6f (Limit: %.6f)\n', res_lpm(idx_sel), R_max);
fprintf('================================================\n');


%% ---------------------------
%  7. VISUALISASI KOMPOSISI PORTOFOLIO (REVISI FIX)
%% ---------------------------

% --- A. PIE CHART (Untuk Lambda Terpilih) ---
% Tampilkan hanya saham dengan bobot > 0.1% agar grafik rapi
threshold_display = 0.001; 
idx_active = w_final > threshold_display;

weights_active = w_final(idx_active);

% Ambil Nama Saham Aktif
names_active = stock_names(idx_active);

% === FIX ERROR DIMENSI DI SINI ===
% Paksa semua variabel menjadi KOLOM (Tegak) agar ukurannya sama
weights_active = weights_active(:); 
names_active   = names_active(:);   

% Konversi ke Persentase untuk Label
percent_labels = arrayfun(@(x) sprintf('%.1f%%', x*100), weights_active, 'UniformOutput', false);
percent_labels = percent_labels(:); % Pastikan ini juga kolom

% Sekarang strcat aman karena semua input adalah kolom dengan panjang sama
final_labels = strcat(names_active, {' ('}, percent_labels, {')'});

figure('Name', 'Detail Alokasi Aset', 'Color', 'w');
p = pie(weights_active);

% Ganti label default angka dengan Nama + Persen
% Trik: pie chart label text objects ada di urutan genap handles
hText = findobj(p, 'Type', 'text');
% Kadang jumlah label tidak pas jika ada slice kecil yg digabung, 
% tapi umumnya aman. Kita pakai Legend saja biar rapi, label di slice kita set kosong atau nama saja.
delete(hText); % Hapus label bawaan yang menumpuk

legend(final_labels, 'Location', 'bestoutside', 'Orientation', 'vertical');
title(sprintf('Alokasi Aset untuk Lambda = %.1f\n(Return: %.2f%%, Risk: %.2f%%)', ...
    lambda_list(idx_sel), res_ret(idx_sel)*100, res_risk(idx_sel)*100), 'FontSize', 12, 'FontWeight', 'bold');


% --- B. STACKED BAR CHART (Evolusi Portofolio) ---
% Grafik ini menunjukkan bagaimana komposisi berubah dari Agresif -> Konservatif
figure('Name', 'Evolusi Komposisi Portofolio', 'Color', 'w');

% Plot Bar Chart Bertumpuk
% Transpose store_weights agar sumbu X adalah iterasi
b = bar(1:num_iter, store_weights', 'stacked');

% Atur Sumbu X agar menampilkan nilai Lambda
set(gca, 'XTick', 1:num_iter, 'XTickLabel', string(lambda_list));
xlabel('Nilai Lambda (Risk Aversion)', 'FontSize', 11, 'FontWeight', 'bold');
ylabel('Bobot Portofolio (0 - 1)', 'FontSize', 11, 'FontWeight', 'bold');
title('Perubahan Komposisi Portofolio: Agresif vs Konservatif', 'FontSize', 14);

% Menambahkan Legend di samping
lgd = legend(stock_names, 'Location', 'eastoutside');
title(lgd, 'Daftar Saham');
grid on;
axis tight;

% --- C. AREA CHART (Alternatif Visualisasi Evolusi - Lebih Halus) ---
figure('Name', 'Area Chart Evolusi', 'Color', 'w');
area(1:num_iter, store_weights');
set(gca, 'XTick', 1:num_iter, 'XTickLabel', string(lambda_list));
xlabel('Nilai Lambda (\lambda)', 'FontSize', 11);
ylabel('Proporsi Aset', 'FontSize', 11);
title('Transisi Alokasi Aset (Risk-Return Trade-off)', 'FontSize', 14);
legend(stock_names, 'Location', 'eastoutside');
grid on;
axis tight;

fprintf('\nVisualisasi berhasil dibuat: Lihat 3 jendela gambar baru.\n');


%% ---------------------------
%  8. EXPORT HASIL KE EXCEL (REVISI PATH)
%% ---------------------------
fprintf('\nMenyimpan hasil rekapitulasi ke Excel...\n');
try
    % 1. Siapkan Header
    clean_stock_names = regexprep(stock_names, '\s', '_');
    header_names = [{'Lambda', 'Expected_Return', 'Risk_StdDev', 'LPM2_Value'}, clean_stock_names];

    % 2. Siapkan Data
    data_matrix = [lambda_list(:), res_ret, res_risk, res_lpm, store_weights'];

    % 3. Buat Tabel
    ResultsTable = array2table(data_matrix, 'VariableNames', header_names);

    % --- PERBAIKAN DI SINI (DEFINISI PATH LENGKAP) ---
    % Simpan file di folder DOWNLOADS agar tidak error permission (C:\ is protected)
    folder_tujuan = "C:\Users\KRISNA BAYU\Downloads\"; 
    output_filename = folder_tujuan + "Hasil_Optimasi_LPM2_Lengkap.xlsx";
    
    % Hapus file lama jika ada (Cek permission write)
    if isfile(output_filename)
        delete(output_filename);
    end
    
    % 4. Tulis ke Excel
    writetable(ResultsTable, output_filename, 'Sheet', 'Rekap_Iterasi');
    fprintf('File berhasil disimpan di: %s\n', output_filename);
    
    % Buka file otomatis
    winopen(output_filename);

catch ME
    fprintf('\n!!! GAGAL MENYIMPAN FILE !!!\n');
    fprintf('Penyebab: %s\n', ME.message);
    fprintf('Solusi: \n1. Tutup file Excel jika sedang terbuka.\n2. Pastikan folder tujuan benar.\n');
end