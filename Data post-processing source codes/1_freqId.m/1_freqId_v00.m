%%---------------------------------------------------------
%INTRODUÇÃO
%---------------------------------------------------------
% Este software usa funções do Signal Processing Toolbox
% OBSERVAÇÕES DA VERSÃO
% Essa função foi desenvolvida para o ensaio EMM-ARM com argamassa feito em
% Dezembro de 2018.
%
% Versão já com as modificações incorporadas desde o teste de validação do
% algoritmo, previsto no plano de trabalho do projeto.
% As funções implementadas foram:
% 1 - Leitura dos dados; 
% 2 - Tratamento com filtro Butterworth (pode deixar opções para ativar outros)
% 3 - Cálculo do PSD (normalizado ou não)
% 4 - Identificação modal (PP + HP e IFT) -
%   4.1 - verificar se o HP foi corrigido;
%   4.2 - verificar a validade de se fazer uma média ponderada para escolher o pico;
% 5 - Reunião de todas as funções acima para ler uma pasta de resultados de ensaio EMM-ARM e
% plotar, ao final, todos os PSDs um ao lado do outro.
% 6 - Plotar também uma curva com apenas os picos
% 7 - Implementar o cálculo do módulo de elasticidade a partir das frequências
% 8 - Plotar o módulo de elasticidade
%
% O arquivo de resultados deverá ser no formato de duas colunas, separadas por vírgulas,
% sendo a primeira coluna referente às acelerações, em valores raw, e a segunda coluna
% referente aos instantes de amostragem, em microssegundos (10^-6 s)
%--------------------------------------------------------
% ESSA VERSÃO TEM UM NOTCH FILTER IMPLEMENTADO.
% NESSA VERSÃO, O FINDPEAKS DESPREZXA FREQU6ÊNCIAS ACIMA DA FREQUÊNCIA DE
% CORTE

clear;
clc;

%%
%---------------------------------------------------------
%CONFIGURAÇÕES INICIAIS DO PROGRAMA
%---------------------------------------------------------
%%
%Define qual filtro será aplicado para a análise modal do sinal:
% 0: dados brutos;
% 1: filtro Butterworth
% 2: filtro Chebyshev
% 3: dados com decimação e filtro Chebyshev
PreProcessAnaliseModal = 1;

nomeArquivoSalvamento = 'FREQUENCIAS-SIST1-0_3_REF.txt'; %Salva as frequências identificadas
nomeArquivoSalvamento2 = 'MAXRMSACCEL-SIST1-0_3_REF.txt'; %Salva as acelerações máxima e RMS
% nomeArquivoSalvamento2 = 'apagueme.txt';

% nomeArquivoSalvamento = 'apagueme.txt';
% nomeArquivoSalvamento2 = 'apagueme.txt';

 notchBottom = 0.1; %Frequência inferior do Notch Filter
 notchUpper = 0.5; %Frequência superior do Notch Filter
 firstNotchFilterFile=3000; %Arquivo a partir do qual será aplicado o primeiro Notch Filter
% notchBottom2 = 21.2; %Frequência inferior do Notch Filter
% notchUpper2 = 22.5; %Frequência superior do Notch Filter
% notchBottom3 = 4; %Frequência inferior do Notch Filter
% notchUpper3 = 5; %Frequência superior do Notch Filter

duracaoSoneca = 5; %Duração da soneca entre duas amostras, em minutos. Padrão: 5 minutos.
desiredFs = 200;
normalized = false; %Define se os PSD utilizados são normalizados ou não.
scaleFactor = 1/2400; %Fator de escala que converte leituras do acelerômetro para g
fc = 40; %Definição da frequência de corte dos filtros (cut-off frequency)
fc_High = 10; %Definição da frequência de corte dos filtros (cut-off frequency)
numPeaks = 3; %Até qual frequência natural o algoritmo irá procurar
ADCZero = 0; %Se o sensor for analógico com zero em 1.5V, é necessário
%centralizar os dados em torno da referência zero.
%PARA ADS1115 COM GANHO 4.096V:
% -ADXL 335: zero = 1.5V -> 12000 LSB
% -MMA 7361: zero = 1.65 V -> 13200 LSB
%Caso for digital, o valor de ADCZero = 0.
fontSize = 8; %Fontsize dos gráficos de time domain e PSD
plotWidth = 15;
plotHeight =8;

%Caixa de diálogo para definição dos headers dos arquivos de salvamento
% prompt = {'Insira nome do arquivo'};
% titulo = 'Input do usuário';
% dims = [1 35];
% definput = {'20','hsv'};
% fileName = char(inputdlg(prompt,titulo,dims,definput));

%Criação da variável "null" a ser utilizada mais adiante
null = [];

%Definição da frequência máxima nas plotagens será a frequência de corte dos filtros
freqMax = fc;
%freqMax = 100;
%Comente alguma das linhas acima para decidir como serão as plotagens
%

%Seleciona diretório dos resultados
[path] = uigetdir();

%Conta quandos arquivos de texto estão no diretório
a=dir([path '/*.txt']);
numeroDeArquivos=size(a,1); %-1 para considerar o arquivo LOGERROR.txt

% numeroDeArquivos=992;
frequenciasObtidasPP = zeros(numeroDeArquivos,3);
frequenciasObtidasIFFT = zeros(numeroDeArquivos,3);
maxAccel = zeros(numeroDeArquivos,3);
rmsAccel = zeros(numeroDeArquivos,3);
temperaturaAmbiente = zeros(numeroDeArquivos,1);
% instanteDeAmostragem = zeros(numeroDeArquivos,1);
% instanteDeAmostragem2 = zeros(numeroDeArquivos,1);
% instanteDeAmostragem3 = zeros(numeroDeArquivos,1);
plotaGraficosNessasRepeticoes = zeros(numeroDeArquivos,1);

NaturalFreqIFFT=zeros(1,numPeaks);


 primeiroArquivo = 1;
%  numeroDeArquivos=500;
% ultimoArquivoMonstro=1146;
% primeiroArquivoMonstro=1018;

tic 
%%
for contadorDeArquivos=primeiroArquivo:numeroDeArquivos
    %%
    %---------------------------------------------------------
    %LEITURA, ARMAZENAMENTO E PLOTAGEM NO DOMÍNIO DO TEMPO
    %---------------------------------------------------------
    %%
    %---------------------------------------------------------
    % Leitura do arquivo de dados
    %---------------------------------------------------------
    %Abre janela de diálogo para selecão do arquivo de amostras a ser lido
    file = sprintf('%08d.txt', contadorDeArquivos) ;
    
    %Cria o endereço da pasta utilizada para salvar os resultados
    savePath=strcat(path,'\');
    
    
    %% ESSA PARTE TEM QUE SER AJUSTADA PARA OS TUBOS 1 E 2, POIS DEPOIS DOS ARQUIVOS ORIGINADOS
    %% PELO ARQUIVO MONSTRO, O CABECALHO VOLTA A TER VALOR IGUAL A 6
%     if contadorDeArquivos<primeiroArquivoMonstro || contadorDeArquivos>ultimoArquivoMonstro
%         %Indica quantas linhas tem o cabeçalho de arquivo de resultados
%         cabecalho = 6;
%     else
        cabecalho = 6;
%     end
    
    %Lê o arquivo com as amostragens. Wrapped entre função try/catch para
    %pegar erros adivindos de arquivos ruins
    try
        M=csvread(fullfile(path,file),cabecalho); %Começa pela primeira linha após o cabeçalho
    catch exception
        M = 0;
    end
    
    
    
    %Começa a ler a partir de uma coluna offset, ignorando cabeçalho do
    %arquivo, caso houver:
    %M=csvread(fullfile(path,file),7,0);
    
    %% TESTA SE O ARQUIVO NÃO ESTÁ VAZIO,
    %Se estiver, passar para o próximo. Os registros desse arquivo são anulados
    
    %O tamanho do primeiro arquivo é tomado como referência de arquivo
    %"bom". Todos os demais são julgados com base nele
    
    if contadorDeArquivos == primeiroArquivo
        %Considera que um arquivo normal de amostragem produzirá um vetor M
        %entre 80% e 120% do primeiro arquivo considerado bom.
        tamanhoPadraoMin = 0.5*length(M);
        tamanhoPadraoMax = 1.2*length(M);
    elseif length(M)<tamanhoPadraoMin || length(M)>tamanhoPadraoMax %Arquivo ruim, pois está zerado
        frequenciasObtidasPP(contadorDeArquivos,:)=0;
        frequenciasObtidasIFFT(contadorDeArquivos,:)=0;
        maxAccel(contadorDeArquivos,1)=0;
        rmsAccel(contadorDeArquivos,1)=0;    
        temperaturaAmbiente(contadorDeArquivos) = 0;
        instanteDeAmostragem(contadorDeArquivos) = instanteDeAmostragem(contadorDeArquivos-1)+duracaoSoneca;
        continue
    end
    
    
    %%
    %---------------------------------------------------------
    %Armazenamento dos resultados experimentais
    %---------------------------------------------------------
    %Tratamento para lidar com medidas que demoraram muito.
    % M(M(:,2) > 4000, :) = [];
    %Ignora a parte final do arquivo de amostragens. Pode ser removido no
    %futuro.
    %comprimento=length(M);
%     M(1:ceil(comprimento*0.15),:) = [];
    
    accelRaw = (-ADCZero+M(:,1 ))*scaleFactor;
    %accelRaw = (-ADCZero+M(:,1));
    time = M(:,2);
    
    maximumAcceleration = max(detrend(accelRaw));
    rmsAcceleration = rms(detrend(accelRaw));
    
    time = time/1000000; %Converte de microssegundos para segundos
    
    %Cria vetor para armazenar a duração de cada amostragem.
    % timeDiff = time;
    
    %As amostragens de tempo são feitas computando apenas o intervalo
    %entre duas medidas consecutivas. Abaixo, o vetor time passa a armazenar
    %o instante absoluto em que a amostra foi tomada
    for i=1:length(time)
        if i>1
            time(i)=time(i)+time(i-1);
        end
    end
    
    %Reamostra os dados para torná-los uniformes!!! Isso é importante porque o
    %Arduino nem sempre toma medidas igualmente espaçadas (ainda mais em
    %frequências muito altas)
    % dummi=2;
    %     [accelRaw, time] = resample(accelRaw,time,desiredFs);
    
    %Seleciona só parte dos vetores accelRaw e time, para evitar distorções do
    %resample:
    % accelRaw([ceil(length(accelRaw)*0.95):length(accelRaw)],:) = [];
    % time([ceil(length(time)*0.95):length(time)],:) = [];
    
    %Calcula o vetor timeDiff com o novo vetor amostrado
    timeDiff = zeros(length(time),1);
    for i=1:length(time)-1
        if i>1
            timeDiff(i)=time(i+1)-time(i);
        end
    end
    
    fs=1/mean(nonzeros(abs(timeDiff)));%Frequência média de amostragem, em Hz.
    
    %%
    %---------------------------------------------------------
    %Pré-processamento do sinal
    %---------------------------------------------------------
    %Retirar a média do sinal
    accelTemp = detrend(accelRaw);
    % accelTemp = accelRaw-1;
    
    
    % ------------------
    % BUTTERWORTH FILTER
    % Design a 8th order lowpass Butterworth filter with cutoff frequency of fc Hz.
    % Aparentemente esse filtro não afeta significativamente a análise no
    % domínio da frequência.
    butOrder = 8; %Ordem do filtro Butterworth
    [bH,aH] = butter(butOrder,fc_High/(fs/2),'high');
    [b,a] = butter(butOrder,fc/(fs/2));
    accelBut = filter(b,a,accelTemp);
    accelBut = filter(bH,aH,accelBut);
    % accelBut = filter(bH,aH,accelTemp);
    
    % ------------------
    % NOTCH FILTER
    % Eliminate the 60 Hz noise with a Butterworth notch filter. Use designfilt to design it
    %Notch 1:
    if contadorDeArquivos>firstNotchFilterFile
    d = designfilt('bandstopiir','FilterOrder',2, ...
               'HalfPowerFrequency1',notchBottom,'HalfPowerFrequency2',notchUpper, ...
               'DesignMethod','butter','SampleRate',fs);
    accelBut = filtfilt(d,accelBut);
    end
    %Notch 2:
%     d = designfilt('bandstopiir','FilterOrder',2, ...
%                'HalfPowerFrequency1',notchBottom2,'HalfPowerFrequency2',notchUpper2, ...
%                'DesignMethod','butter','SampleRate',fs);
%     accelBut = filtfilt(d,accelBut);
%     %Notch 3:
%     d = designfilt('bandstopiir','FilterOrder',2, ...
%                'HalfPowerFrequency1',notchBottom3,'HalfPowerFrequency2',notchUpper3, ...
%                'DesignMethod','butter','SampleRate',fs);
%     accelBut = filtfilt(d,accelBut);
%     
           
    % -----------------
    % CHEBYSHEV FILTER
    % Design a 8th order lowpass Chebyshev filter with cutoff frequency of fc Hz.
    % Aparentemente esse filtro não afeta significativamente a análise no
    % domínio da frequência.
%     chebOrder = 8;
%     dBpassband = 0.01;
%     [b,a] = cheby1(chebOrder,dBpassband,fc/(fs/2));
%     accelCheb = filter(b,a,accelTemp);
    
    % -----------------
    % DECIMAÇÃO (reamostragem)
    % Rodrigues (2004): Fazer o processo de decimação, que consiste na
    % reamostragem ou passagem das séries de resposta digitalizadas para uma
    % frequência de amostragem mais baixa. Para efectuar esta operação é
    % necessário filtrar as séries com um filtro passa-baixo com uma frequência
    % de corte de cerca de 0,4 da nova frequência de amostragem, para evitar
    % erros de aliasing nas séries decimadas.
%     r = round(fs/fc); %fator de decimação
%     accelDec = decimate(accelTemp,r);
%     timeDec = decimate(time,r);
    %%
    %---------------------------------------------------------
    %Visualização da resposta no tempo do sistema
    %---------------------------------------------------------
    
    if plotaGraficosNessasRepeticoes(contadorDeArquivos) == 1
        %Plota a amostragem no domínio do tempo
        ax1 = subplot(1,2,1); % top subplot
        
        %Retire os comentários abaixo para plotar os gráficos necessários
        %plot(ax1,time,accelRaw,'-b'); %Plot raw signal
        %hold on
        plot(ax1,time,accelBut,'-r'); %Plot filtered signal
        hold on
        %plot(ax1,time,accelCheb,'--g'); %Plot filtered signal
        %hold on
        %plot(ax1,timeDec,accelDec,'.k'); %Plot pre-processed signal
        
        %Configurações da plotagem
        title(ax1,{'Acceleration signal','Time domain'});
        xlabel(ax1,'Time (seg)');
        ylabel(ax1,'Acceleration (g)');
        set(gca,'FontSize',fontSize)
        legend('Butterworth filtered', 'Chebyshev filtered', 'Decimated');
        
        %Permite inserir algum comentário na plotagem, no formato de uma caixa de
        %texto de dimensões do vetor dim e conteúdo da string str
        %dim = [0.6 0.25 0 0.1];
        %str = "Excitação: 3 puxões + 5 toques + 1/2 puxões." + newline + "Amostragem a 700 Hz";
        %annotation('textbox',dim,'String',str,'FitBoxToText','on');
    end
    
    
    %%
    %---------------------------------------------------------
    % PLOTAGEM DO DFT, PSD E IDENTIFICAÇÃO DOS PICOS - PEAK PICKING
    %---------------------------------------------------------
    %%
    %---------------------------------------------------------
    % Definição de qual sinal filtrado será utilizado de agora em diante
    %---------------------------------------------------------
    %Define qual filtro será aplicado para a análise modal do sinal:
    % 0: dados brutos;
    % 1: filtro Butterworth
    % 2: filtro Chebyshev
    % 3: dados com decimação e filtro Chebyshev
    switch PreProcessAnaliseModal
        case 0
            accel = accelRaw;
        case 1
            accel = accelBut;
        case 2
            accel = accelCheb;
        case 3
            accel = accelDec;
            time = timeDec;
            fs = fs/r;
        otherwise
            warning('Selecione um método de pré-processamento para a análise modal');
    end
%     %%
%     %---------------------------------------------------------
%     %Cálculo a DFT do sinal utilizando o algoritmo FFT
%     %---------------------------------------------------------
%     L = length(accel); %Comprimento da amostragem, isto é, o número de pontos.
%     Y = fft(accel); %Calcula a DFT do sinal (é uma função complexa)
%     P2 = abs(Y/L); %Obtém somente o "one-sided spectrum" do sinal. Divide por L
%     %como um fator de escala, para normalizar a energia da fft
%     %em relação à quantidade de pontos utilizados no cálculo
%     fftP1 = P2(1:(L/2+1)); %Obtém apenas uma parte do "two-sided spectrum"
%     fftP1(2:end-1) = 2*fftP1(2:end-1); %Multiplica por dois para obter obter o "one-sided spectrum"
%     fftFreq = fs*(0:(L/2))/L; %Define o domínio- da frequência: as "bins"
%     %em que se calcula a frequência, ou a
%     %resolução do método
%     %%
%     %---------------------------------------------------------
%     %Plotagem da FFT do sinal
%     %---------------------------------------------------------
%     % ax2 = subplot(3,1,2); % middle subplot
%     % plot(ax2,fftFreq,fftP1)
%     % title(ax2,'Single-Sided Amplitude Spectrum - FFT algorithm MATLAB')
%     % xlabel(ax2,'Frequency (Hz)')
%     % ylabel(ax2,'g (m/s^{2})') %A função FFT no MATLAB retorna valores de amplitude com
%     %                           %unidades iguais às do vetor de entrada: nesse caso, g.
%     % set(gca,'FontSize',10)
%     % xlim([0 freqMax])
%     % ylim([0 1.2*max(fftP1)])
%     % hold on;
%     
%     %Permite inserir algum comentário na plotagem, no formato de uma caixa de
%     %texto de dimensões do vetor dim e conteúdo da string str
%     %dim = [0.6 0.25 0 0.1];
%     %str = "Excitação: 3 puxões + 5 toques + 1/2 puxões." + newline + "Amostragem a 700 Hz";
%     %annotation('textbox',dim,'String',str,'FitBoxToText','on');
%     %%
%     %---------------------------------------------------------
%     %Método Peak Picking aplicado ao FFT, para posterior plotagem
%     %---------------------------------------------------------
%     %Determina os pontos de pico do espectro de DFT e tenta relacioná-los às
%     %frequências do sistema por comparação dos picos.
%     %As seguintes suposições são feitas para lidar com o caso de picos muito
%     %próximos devido a ruídos do sistema:
%     %   1. Dois picos separados entre si de um valor menor que "threshold" (%)
%     %   da frequência relacionada ao pico não correspondem a picos distintos. O
%     %   ponto de menor densidade espectral de energia é descartado.
%     %   2. O código considera apenas os "numFrequencia" picos mais altos, que
%     %   serão referentes às "numFrequencia" primeiras frequências naturais do
%     %   sistema, onde "numFrequencia" é uma variável definida pelo usuário.
%     %---------------------------------------------------------
%     
%     [peaks, freq] = findpeaks(fftP1,fftFreq);
%     threshold = 0.1; %Valor, em %, da faixa em torno de um pico que considera as frequências como iguais.
%     infLim = 1 - threshold;
%     supLim = 1 + threshold;
%     freq = freq.';
%     freq_peaksFFT = [freq peaks]; %Cria um vetor com frequências na primeira coluna
%     %e os picos na segunda
%     for i=1:length(freq)
%         for j=i+1:length(freq)
%             testedValue = freq_peaksFFT(i,1);
%             referenceValue = freq_peaksFFT(j,1);
%             %Checa se o valor de pico de índice j se refere à uma frequência
%             %próxima o suficiente da frequência do pico de índice i. Se sim,
%             %ambos os picos se referem à mesma frequência e devem ser
%             %considerados apenas uma vez.
%             if testedValue>infLim*referenceValue && testedValue<supLim*referenceValue
%                 %Aqui, apenas o pico com maior valor é considerado.
%                 if freq_peaksFFT(i,2)<freq_peaksFFT(j,2)
%                     freq_peaksFFT(i,2)=0;
%                     freq_peaksFFT(i,1)=0;
%                     %Elimina esses valores das próximas checagens
%                 elseif freq_peaksFFT(i,2)>freq_peaksFFT(j,2)
%                     freq_peaksFFT(j,2)=0;
%                     freq_peaksFFT(j,1)=0;
%                     %Elimina esses valores das próximas checagens
%                 end
%             else
%                 break
%             end
%         end
%     end
%     
%     %Parte do código não debugada ainda
%     NaturalFreqFFT =sortrows(fliplr(freq_peaksFFT), 'descend');
%     list_of_lines_to_delete = numPeaks+1:1:length(NaturalFreqFFT);
%     NaturalFreqFFT(list_of_lines_to_delete,:) = [];
%     NaturalFreqFFT = sortrows(NaturalFreqFFT, 'descend');
    %%
    %---------------------------------------------------------
    %Plotagem dos picos identificados com PP sobre o gráfico da DFT
    %---------------------------------------------------------
    % for i=1:numPeaks
    %     plot (NaturalFreqFFT(i,2),NaturalFreqFFT(i,1), '*r', 'MarkerSize', 5)
    %     hold on;
    %     textString = sprintf('f = %.3f Hz', NaturalFreqFFT(i,2));
    %     text(NaturalFreqFFT(i,2)+2, NaturalFreqFFT(i,1)+.035*max(NaturalFreqFFT(:,1)), textString, 'FontSize', 10);
    % end
    % hold off
    %%
    %---------------------------------------------------------
    %Cálculo do PSD (power spectral density) do sinal utilizando o procedimento
    %de Welch (partição dos dados em vários conjuntos com sobreposição,
    %utilização da função janela de Hamming, e obtenção do PSD final a partir
    %da média dos PSD de cada trecho).
    %---------------------------------------------------------
    
    % nfft = 2^nextpow2(length(accel)/2); %https://stackoverflow.com/questions/29439888/what-is-nfft-used-in-fft-function-in-matlab
    % [pxx, fWelch] = pwelch(accel, hann(nfft), nfft/2, nfft, fs); %https://stackoverflow.com/questions/22661758/how-to-improve-the-resolution-of-the-psd-using-matlab
    %  [pxx,fWelch] = pwelch(accel,null,null,[],fs); %Granja utiliza 16384 pontos para FFT - pg. 101
    [pxx,fWelch] = pwelch(accel,null,null,16384,fs); %Granja utiliza 16384 pontos para FFT - pg. 101
    %%
    %---------------------------------------------------------
    %Plotagem do PSD do sinal
    %--------------------------------------------------------
    %Define o título do gráfico a depender se a opção selecionada é normalizada
    %ou não
    
    if plotaGraficosNessasRepeticoes(contadorDeArquivos) == 1
        if normalized == false
            normalizedPXX = 1;
            PSD_y_label='PSD (g^{2}/Hz)';
            PSD_title={'Power Spectral Densitity (PSD) estimate','Welch Procedure'};
        else
            normalizedPXX=sum(pxx);
            PSD_y_label='NPSD (amplitude)';
            PSD_title={'Normalized Power Spectral Densitity (NPSD) estimate','Welch Procedure'};
        end
        
        %Instruções de plotagem
        ax3 = subplot(1,2,2); % bottom subplot
        plot(ax3,fWelch,pxx/normalizedPXX);
        hold on
        title(ax3,PSD_title);
        xlabel(ax3,'Frequency (Hz)');
        ylabel(ax3,PSD_y_label);
        set(gca,'FontSize',fontSize)
        xlim([0 freqMax])
        ylim([0 1.2*max(pxx)/normalizedPXX])
    end
    
    %Permite inserir algum comentário na plotagem, no formato de uma caixa de
    %texto de dimensões do vetor dim e conteúdo da string str
    %dim = [0.6 0.25 0 0.1];
    %str = "Excitação: 3 puxões + 5 toques + 1/2 puxões." + newline + "Amostragem a 700 Hz";
    %annotation('textbox',dim,'String',str,'FitBoxToText','on');
    %%
    %---------------------------------------------------------
    %Método Peack-Picking aplicado ao PSD
    %---------------------------------------------------------
    %Determina os pontos de pico do PSD de Welch e tenta relacioná-los às
    %frequências do sistema por comparação dos picos.
    %As seguintes suposições são feitas para lidar com o caso de picos muito
    %próximos devido a ruídos do sistema:
    %   1. Dois picos separados entre si de um valor menor que "threshold" (%)
    %   da frequência relacionada ao pico não correspondem a picos distintos. O
    %   ponto de menor densidade espectral de energia é descartado.
    %   2. O código considera apenas os "numFrequencia" picos mais altos, que
    %   serão referentes às "numFrequencia" primeiras frequências naturais do
    %   sistema, onde "numFrequencia" é uma variável definida pelo usuário.
    %---------------------------------------------------------
    
    cutLength = 2*round(length(pxx)*(fc/fs)); %Desprezar as frequências acima da frequência de corte fc
    [peaks, freq] = findpeaks(pxx(1:cutLength),fWelch(1:cutLength));
    threshold = 0.1; %Insert a threshold value in decimal form of a %
    infLim = 1 - threshold;
    supLim = 1 + threshold;
    numFrequencia = numPeaks; %Identificar apenas as "numFrequencia" primeiras frequências
    freq_peaks = [freq peaks]; %Create a vector with frequencies in the first
    %column and peaks in the second
    
    for i=1:length(freq)
        for j=i+1:length(freq)
            testedValue = freq_peaks(i,1);
            referenceValue = freq_peaks(j,1);
            %Checa se o valor de pico de índice j se refere à uma frequência
            %próxima o suficiente da frequência do pico de índice i. Se sim,
            %ambos os picos se referem à mesma frequência e devem ser
            %considerados apenas uma vez.
            if testedValue>infLim*referenceValue && testedValue<supLim*referenceValue
                %Aqui, apenas o pico com maior valor é considerado.
                if freq_peaks(i,2)<freq_peaks(j,2)
                    freq_peaks(i,2)=0;
                    freq_peaks(i,1)=0;
                    %Elimina esses valores das próximas checagens
                elseif freq_peaks(i,2)>freq_peaks(j,2)
                    freq_peaks(j,2)=0;
                    freq_peaks(j,1)=0;
                    %Elimina esses valores das próximas checagens
                end
            else
                break
            end
        end
    end
    
    NaturalFreq = sortrows(fliplr(freq_peaks), 'descend');
    list_of_lines_to_delete = numPeaks+1:1:length(NaturalFreq);
    NaturalFreq(list_of_lines_to_delete,:) = [];
    NaturalFreq = sortrows(NaturalFreq, 'descend');
    %%
    %---------------------------------------------------------
    %Plotagem dos picos identificados com Peak Picking
    %Plota os picos identificados no PSD de Welch
    %---------------------------------------------------------
    
    if plotaGraficosNessasRepeticoes(contadorDeArquivos) == 1
        plot(fWelch,pxx/normalizedPXX);
        hold on
        
        for i=1:numPeaks
            plot (NaturalFreq(i,2),NaturalFreq(i,1)/normalizedPXX, '*r', 'MarkerSize', 5)
            hold on;
            textString = sprintf('f = %.3f Hz', NaturalFreq(i,2));
            text(NaturalFreq(i,2)+2, NaturalFreq(i,1)+.035*max(NaturalFreq(:,1)), textString, 'FontSize', fontSize);
        end
        hold off
        %set(gcf, 'units','pixels', 'Position', [0, 0, 1000, 1000])
        %Ajusta  o tamanho da plotagem.
        set(gcf, 'units','centimeters', 'Position', [0, 0, plotWidth, plotHeight]);
        %%
        %---------------------------------------------------------
        %Salva as plotagens até aqui (sinal no tempo e na frequência) no formato .fig e .emf
        %---------------------------------------------------------
        %set(gcf, 'units','pixels', 'Position', [0, 0, 1000, 1000]); %Ajusta  o tamanho da plotagem.
        tempName = '_Sinal no tempo e na frequência';
        saveName = strcat(fileName,tempName);
        saveas(gcf,fullfile(savePath,saveName),'fig');
        saveas(gcf,fullfile(savePath,saveName),'emf');
    end
    
    
%     %%
%     %---------------------------------------------------------
%     % DETERMINAÇÃO DO AMORTECIMENTO PELO MÉTODO DA MEIA POTÊNCIA
%     %---------------------------------------------------------
%     %%
%     %---------------------------------------------------------
%     %Esse método é baseado em Rodrigues (2004), pg 131 e em
%     %Granja (2016), pg 102.
%     % Pode-se utilizar métodos de interpolação para os pontos de meia potência,
%     % segundo Rodrigues (2004):
%     % 1 - interpolação linear
%     % 2 - ajuste de uma parábola aos três pontos de maior amplitude
%     % 3 - ajuste de uma spline em torno dos valores de pico
%     %Nesse código é utilizada uma interpolação linear
%     %---------------------------------------------------------
%     dampHalfPower=zeros(numPeaks,1);
%     deltaWelch = fWelch(2)-fWelch(1);%Diferença entre dois elementos de fWelch
%     deltaF = 1; %Variação em torno do pico em estudo que define o trecho ajustado
%     thresholdIndex = round(deltaF/deltaWelch); %Variação +- deltaF em termos de índices de fWelch
%     
%     if plotaGraficosNessasRepeticoes(contadorDeArquivos) == 1
%         fig2 = figure;
%     end
%     
%     for i=1:numPeaks
%         %-----------------
%         %Selecionar a parte do PSD correspondente à i-th frequência que será
%         %utilizada no ajuste.
%         %-----------------
%         %Índice em fWelch do pico em análise
%         index = find(fWelch==NaturalFreq(i,2),1);
%         %Determina a potência no pico do PSD
%         potMax = pxx(index);
%         %Determina a frequência no pico do PSD
%         freqMax = fWelch(index);
%         
%         %Procura, à esquerda do pico, o primeiro ponto cuja a potência seja
%         %menor que a metade da potência de pico
%         esqIndex=index;
%         spotEsq = 0;
%         while pxx(esqIndex)>potMax/2
%             esqIndex=esqIndex-1;
%             if esqIndex == 0
%                 esqIndex = 1;
%                 %Fim do sinal
%                 break
%             end
%             if pxx(esqIndex)==potMax/2
%                 spotEsq = 1; %Na mosca! Exatamente a potência média!
%                 break
%             end
%         end
%         
%         %Procura, à direita do pico, o primeiro ponto cuja a potência seja
%         %menor que a metade da potência de pico
%         dirIndex=index;
%         spotDir = 0;
%         while pxx(dirIndex)>potMax/2
%             dirIndex=dirIndex+1;
%             if dirIndex > length(pxx)
%                 dirIndex = length(pxx);
%                 %Fim do sinal
%                 break
%             end
%             if pxx(dirIndex)==potMax/2
%                 spotDir = 1; %Na mosca! Exatamente a potência média!
%                 break
%             end
%         end
%         
%         %Se as frequências encontradas anteriormente não corresponderem
%         %a potências exatamente iguais a metade da potência de pico, efetuar
%         %uma inteporlação linear com os valores das séries de amostras
%         if spotEsq == 0
%             deltaW =((potMax/2)-pxx(esqIndex))*(fWelch(esqIndex+1)-fWelch(esqIndex))/(pxx(esqIndex+1)-pxx(esqIndex));
%             w1 = fWelch(esqIndex)+deltaW;
%             p1 = potMax/2;
%         else
%             w1=fWelch(esqIndex);
%             p1=pxx(esqIndex);
%         end
%         if spotDir == 0
%             deltaW =((potMax/2)-pxx(dirIndex))*(fWelch(dirIndex)-fWelch(dirIndex-1))/(pxx(dirIndex-1)-pxx(dirIndex));
%             w2 = fWelch(dirIndex)-deltaW;
%             p2 = potMax/2;
%         else
%             w2=fWelch(dirIndex);
%             p2=pxx(dirIndex);
%         end
%         
%         %Cálculo do coeficiente de amortecimento pelo método da meia potência
%         dampHalfPower(i)=(w2-w1)/(w2+w1);
%         
%         %-----------------
%         %Plotagem dos resultados
%         %-----------------
%         %Define o trecho do PSD de interesse para o modo estudado
%         m = 1;
%         xdata = zeros(1,2*thresholdIndex+1);
%         ydata = zeros(1,2*thresholdIndex+1);
%         
%         %Evita erros durante a leitura de arquivos de dados ruins
%         if (index-thresholdIndex)<=0
%             thresholdIndex=index-1;
%         end
%         
%         for k=(index-thresholdIndex):(index+thresholdIndex)
%             xdata(m) = fWelch(k);
%             ydata(m) = pxx(k);
%             m = m +1;
%         end
%         
%         if plotaGraficosNessasRepeticoes(contadorDeArquivos) == 1
%             ax = subplot(numPeaks,1,i);
%             %Plota o espectro de potência
%             plot(ax,xdata,ydata,'ro-','MarkerSize', 5);
%             hold on;
%             %Obtém os limites do gráfico para ajustes posteriores
%             xlim([xdata(1) xdata(end)])
%             ylim([min(ydata) 1.25*max(ydata)])
%             xLim = xlim; %Vetor com os valores limites de x no gráfico
%             yLim = ylim; %Vetor com os valores limites de y no gráfico
%             %Plota os pontos de meia potência utilizados no cálculo do coeficiente
%             %de amortecimento
%             plot (freqMax,potMax, 'sb', 'MarkerSize', 8,'MarkerFaceColor','b');
%             plot (w1,p1, 'sb', 'MarkerSize', 8,'MarkerFaceColor','b');
%             plot (w2,p2, 'sb', 'MarkerSize', 8,'MarkerFaceColor','b');
%             hold on;
%             %Acrescenta as frequências e potências relativas aos pontos marcados
%             str = {'\omega_{peak}'};
%             text(freqMax, potMax+0.075*yLim(2), str, 'FontSize', fontSize);
%             str = {'\omega_1'};
%             text(w1-0.015*(xLim(2)-xLim(1)), p1+0.075*yLim(2), str, 'FontSize', fontSize);
%             str = {'\omega_2'};
%             text(w2, p2+0.075*yLim(2), str, 'FontSize', fontSize);
%             %Desenha uma linha para marcar os pontos utilizados para cálculo do
%             %amortecimento
%             grayAlpha = 0.5; %Define o tom de cinza da linha (mais claro quanto
%             %mais próximo de 1
%             line([xLim(1);w1],[p1;p1],'linestyle','--','color',[0,0,0]+grayAlpha);
%             line([w1;w1],[yLim(1);p1],'linestyle','--','color',[0,0,0]+grayAlpha);
%             line([xLim(1);w2],[p2;p2],'linestyle','--','color',[0,0,0]+grayAlpha);
%             line([w2;w2],[yLim(1);p2],'linestyle','--','color',[0,0,0]+grayAlpha);
%             %Insere títulos, legenda, identificação dos eixos, e caixa de texto com
%             %coeficiente de amortecimento estimado
%             %str = {['Mode ', num2str(i)]};
%             title(ax,['Half Power method - Mode ',num2str(i)]);
%             xlabel(ax,'Frequency (Hz)');
%             ylabel(ax,'PSD (g^{2}/Hz)');
%             set(gca,'FontSize',fontSize);
%             legend('Experimental data');
%             str = {['\bfDamping ratio (\xi_{',num2str(i),'}): \rm',num2str(dampHalfPower(i)*100),' %'],...
%                 ['\omega_{peak}: ',sprintf('f=%.3f Hz', freqMax)],...
%                 ['\omega_1: ',sprintf('f=%.3f Hz', w1)],...
%                 ['\omega_2: ',sprintf('f=%.3f Hz', w2)]};
%             %t = text(xLim(2)-0.3*(xLim(2)-xLim(1)),(yLim(1)+yLim(2))/2,str,'cyan','FontSize', fontSize);
%             t = text(xLim(1)+0.05*(xLim(2)-xLim(1)),(yLim(1)+yLim(2))*0.75,str,'cyan','FontSize',fontSize);
%             t.EdgeColor = 'black';
%         end
%     end
%     
%     
%     %%
%     %---------------------------------------------------------
%     %Salva as plotagens até aqui (parâmetros modais pela meia potência) no formato .fig e .emf
%     %---------------------------------------------------------
%     if plotaGraficosNessasRepeticoes(contadorDeArquivos) == 1
%         %Ajusta  o tamanho da plotagem.
%         set(gcf, 'units','centimeters', 'Position', [0, 0, plotWidth, plotHeight]);
%         %set(gcf, 'units','pixels', 'Position', [0, 0, 1000, 1000]); %Ajusta  o tamanho da plotagem.
%         tempName = '_Parâmetros modais - Meia Potência';
%         saveName = strcat(fileName,tempName);
%         saveas(gcf,fullfile(savePath,saveName),'fig');
%         saveas(gcf,fullfile(savePath,saveName),'emf');
%     end
%     
%     
    %%
    %---------------------------------------------------------
    % DETERMINAÇÃO DO AMORTECIMENTO PELO AJUSTE DO ESPECTRO ANALÍTICO
    %---------------------------------------------------------
    %%
    %---------------------------------------------------------
    %Determinação dos parâmetros modais pelo ajuste do espectro
    %analíico de um sistema de 1 GL
    %Esse método é baseado em Rodrigues (2004), pg 132
    %---------------------------------------------------------
    % %Vetor com os parâmetros analíticos a serem ajustados
    % x=zeros(4,numPeaks);
    % deltaWelch = fWelch(2)-fWelch(1);%Diferença entre dois elementos de fWelch
    % deltaF = 0.5; %Variação em torno do pico em estudo que define o trecho ajustado
    % thresholdIndex = round(deltaF/deltaWelch); %Variação +- deltaF em termos de índices de fWelch
    % fig3 = figure;
    %
    % for i=1:numPeaks
    %     %-----------------
    %     %Selecionar a parte do SPD correspondente à i-th frequência que será
    %     %utilizada no ajuste.
    %     %-----------------
    %     %Índice em fWelch do pico em análise
    %     index = find(fWelch==NaturalFreq(i,2),1);
    %     %Define a parte do SPD a ser ajustada pelos parâmetros
    %     m = 1;
    %     xdata = zeros(1,2*thresholdIndex+1);
    %     ydata = zeros(1,2*thresholdIndex+1);
    %     for k=(index-thresholdIndex):(index+thresholdIndex)
    %         xdata(m) = fWelch(k);
    %         ydata(m) = pxx(k);
    %         m = m +1;
    %     end
    %
    %     %-----------------
    %     %Definir a função analítica que descreve a resposta em frequência de
    %     %um sistema de 1 GL que será ajustada ao trecho em análise
    %     %-----------------
    %     %Função do espectro analítico
    %     fun = @(x,xdata)x(1)*((abs(((xdata*2*pi).^2)./(1-((xdata*2*pi/(2*pi*x(2))).^2)+1j*2*x(3)*(2*pi*xdata/(2*pi*x(2)))))).^2)+x(4);
    %     %A função "fun" depende de quatro parâmetros x1, x2, x3, x4. A
    %     %correspondência desses parâmetros às variáveis modais pode ser feita
    %     %checando Rodrigues (2004), pg 132.
    %
    %     %-----------------
    %     %Ajuste da função analítica aos dados experimentais, por meio do método
    %     %de levenberg-marquardt (mínimos quadrados)
    %     %-----------------
    %     %Ponto de início da função a ser ajustada: valores de x(i), i = 1 a 4
    %     x0=[pxx(1)/10^6,fWelch(index),dampHalfPower(i),(ydata(1)+ydata(m-1))/2];
    %     %Definição do método de ajuste
    %     options = optimoptions('lsqcurvefit','Algorithm','levenberg-marquardt');
    %     lb = [];
    %     ub = [];
    %     %Obtenção dos parâmetros de ajuste da função.
    %     x(:,i) = lsqcurvefit(fun,x0,xdata,ydata,lb,ub,options);
    %
    %     %-----------------
    %     %Plotagem dos resultados
    %     %-----------------
    %
    %     times = linspace(xdata(1),xdata(end));
    %     xtemp = x(:,i);
    %     ax = subplot(numPeaks,1,i);
    %     plot(ax,xdata,ydata,'b-',times,fun(xtemp,times),'m-'); %Plot pre-processed signal
    %     str = {['Mode ', num2str(i)]};
    %     str = join(str);
    %     title(ax,{['Curve-fitting SDOF response - ',char(str)]});
    %     xlabel(ax,'Frequency (Hz)');
    %     ylabel(ax,'PSD (g^{2}/Hz)');
    %     set(gca,'FontSize',fontSize);
    %     legend('Experimental data','Adjusted analytical spectrum');
    %     str = {['\bf Natural Frequency: \rm', num2str(x(2,i)),' Hz'],['\bf Damping ratio: \rm',num2str(x(3,i)*100),' %']};
    %     xlim([xdata(1) xdata(end)])
    %     ylim([min(fun(xtemp,times)) 1.25*max(max(fun(xtemp,times)),max(ydata))])
    %     xLim = xlim;
    %     yLim = ylim;
    %     t = text(xLim(1)+0.05*(xLim(2)-xLim(1)),(yLim(1)+yLim(2))*0.9,str,'cyan','FontSize',fontSize);
    %     t.EdgeColor = 'black';
    % end
    % %set(gcf, 'units','pixels', 'Position', [0, 0, 1000, 1000])
    % set(gcf, 'units','centimeters', 'Position', [0, 0, plotWidth, plotHeight]); %Ajusta  o tamanho da plotagem.
    % %%
    % %---------------------------------------------------------
    % %Salva as plotagens até aqui (parâmetros modais por ajuste do espectro analítico) no formato .fig e .emf
    % %---------------------------------------------------------
    % %set(gcf, 'units','pixels', 'Position', [0, 0, 1000, 1000]); %Ajusta  o tamanho da plotagem.
    % tempName = '_Parâmetros modais - Espectro analítico';
    % saveName = strcat(fileName,tempName);
    % saveas(gcf,fullfile(savePath,saveName),'fig');
    % saveas(gcf,fullfile(savePath,saveName),'emf');
    %
    
    
%     %%
%     %---------------------------------------------------------
%     % MÉTODO IFT DE ANÁLISE MODAL
%     %---------------------------------------------------------
%     %%
%     %---------------------------------------------------------
%     %Cálculo da FFT do sinal, utilizada para transposição do domínio da
%     %frequência para tempo
%     %---------------------------------------------------------
%     fftY=fft(accel);
%     FfftY=linspace(-1,1,L)*fs/2;
%     %Calcula o espectro one-sided, utilizado em plotagens
%     P2 = abs(fftY/L);
%     fftYoS = P2(1:(L/2+1)); %Obtém apenas uma parte do "two-sided spectrum"
%     fftYoS(2:end-1) = 2*fftYoS(2:end-1); %Multiplica por dois para obter obter o "one-sided spectrum"
%     FfftYoS = fs*(0:(L/2))/L; %Define o domínio da frequência: as "bins"
%     %em que se calcula a frequência, ou a
%     %resolução do método
%     %Calcula uma versão "normalizada" do vetor da FFT do sinal, mais fácil de
%     %plotar para debugar
%     fftY_norm=[fftY(floor((L/2))+2:L); fftY(1:floor((L/2))+1)];
%     halfFFT=L-(L/2)+2;
%     %Plota para debug
%     %fig3 = figure;
%     %plot(FfftY,2*abs(fftY_norm));
%     %%
%     %---------------------------------------------------------
%     %Método IFFT: seleção de regiões do FFT, a partir dos picos identificados
%     %no PSD, e transposição para o domínio do tempo, no qual a frequência e o
%     %coeficiente de amortecimento são calculados com base n
%     %---------------------------------------------------------
%     x=zeros(2,numPeaks); %Vetor com os parâmetros da curva a serem ajustados para determinação da
%     %frequência natural
%     deltaWelch = FfftY(2)-FfftY(1);%Diferença entre dois elementos de fWelch
%     deltaF = 2; %Variação em torno do pico em estudo que terá ganho 1
%     deltaFgauss = 2; %Tamanho da cauda da função gaussiana, desde a extremidade da função retangular, de ganho 1, até o ponto de ganho redPercent
%     redPercent = 0.01; %Redução desejada no filtro gaussiano, em %, na extremidade igual à deltaFgauss/2
%     nPeaks = 100; %Quantidade de picos a serem utilizados para ajuste do decremento.
%     thresholdIndex = round(deltaF/deltaWelch); %Variação +- deltaF em termos de índices de fWelch
%     
%     if plotaGraficosNessasRepeticoes(contadorDeArquivos) == 1
%         fig4 = figure;
%     end
%     
%     repeatition = 0;
%     
%     for i=1:numPeaks
%         %%
%         %-----------------
%         %SELEÇÃO DO TRECHO DO FFT
%         %Selecionar a parte do FFT correspondente à i-th frequência que será
%         %utilizada na identificação modal no domínio do tempo.
%         %-----------------
%         
%         %Determinação do indice no vetor de frequências do FFT relativo ao pico em análise:
%         %Como o pico foi calculado a partir do PSD, a correspondência não é
%         %exata e deve ser calculada como a melhor aproximação possível
%         goal=NaturalFreq(i,2);
%         dist = abs(FfftY - goal);
%         minDist = min(dist((round(length(FfftY)/2):end)));
%         index = (dist == minDist); %Ao invés de usar a função find, usa índices lógicos (recomendação do MATLAB)
%         
%         %Define a parte do FFT a ser utilizada na identificação modal
%         xdataPart = FfftY;
%         ydataPart = zeros(1,length(fftY));
%         
%         %Filtro gaussiano
%         gauss = zeros(1,length(ydataPart));
%         shiftRight = mean(FfftY(index));
%         sigma = (-deltaFgauss*deltaFgauss/(8*log(redPercent)))^0.5;
%         for n=1:length(gauss)
%             if FfftY(n)<-deltaF+shiftRight
%                 gauss(n)=exp(-(FfftY(n)-shiftRight+deltaF).^ 2 / (2 * sigma ^ 2));
%                 gauss(-n+length(gauss)+1)=exp(-(FfftY(n)-shiftRight+deltaF).^ 2 / (2 * sigma ^ 2));
%             elseif FfftY(n)<deltaF+shiftRight
%                 gauss(n)=1;
%                 gauss(-n+length(gauss)+1)=1;
%             else
%                 gauss(n)=exp(-(FfftY(n)-shiftRight-deltaF).^ 2 / (2 * sigma ^ 2));
%                 gauss(-n+length(gauss)+1)=exp(-(FfftY(n)-shiftRight-deltaF).^ 2 / (2 * sigma ^ 2));
%             end
%         end
%         
%         %Seleciona a parte do fftY necessário
%         %     for k=(index-thresholdIndex):(index+thresholdIndex)
%         %         ydataPart(k) = fftY_norm(k);
%         %         ydataPart(L-k)=fftY_norm(L-k);
%         %     end
%         %Aplica o filtro gaussiano
%         ydataPart = fftY_norm;
%         ydataPart = ydataPart.*gauss.';
%         ydataPart = ydataPart.';
%         
%         if plotaGraficosNessasRepeticoes(contadorDeArquivos) == 1
%             %Plotar o trecho do PSD estudado
%             ax = subplot(numPeaks,4,i+repeatition);
%             %plot(xdataPart,abs(ydataPart));
%             plot(xdataPart(round(length(xdataPart)/2):end),2*abs(ydataPart(round(length(ydataPart)/2):end)));
%             str = {['Mode ', num2str(i)]};
%             str = join(str);
%             title(ax,{['FFT region selected - ',char(str)]});
%             xlabel(ax,'Frequency (Hz)');
%             ylabel(ax,'Normalized amplitude (-)');
%         end
%         %%
%         %-----------------
%         %TRANSFORMADA INVERSA DE FOURIER
%         %Calcula a transformada inversa de Fourier do trecho selecionado
%         %-----------------
%         %Ajusta o ydataPart para se referir a fftY e não a fftY_norm
%         ydataPart = [ydataPart(floor(L/2)+1:end) ydataPart(1:floor(L/2))];
%         ifftY = (ifft(ydataPart,'symmetric'));
%         timeifft=time;
%         
%         if plotaGraficosNessasRepeticoes(contadorDeArquivos) == 1
%             %Plota o sinal no tempo após ifft
%             ax = subplot(numPeaks,4,i+1+repeatition);
%             plot(ax,timeifft,ifftY);
%             str = {['Mode ', num2str(i)]};
%             str = join(str);
%             title(ax,{['IFFT of the selected FFT region - ',char(str)]});
%             xlabel(ax,'Time (seconds)');
%             ylabel(ax,'Amplitude (-)');
%         end
%         
%         %%
%         %-----------------
%         %IDENTIFICAÇÃO MODAL DA FREQUÊNCIA
%         %Investiga quais os pontos passam por zero para determinação da
%         %frequência
%         %-----------------
%         ifftYZeros = zeros(1,length(ifftY));
%         index = 1;
%         for m=2:length(ifftY)+1
%             if (ifftY(m-1)<0 && ifftY(m)>0)||(ifftY(m-1)>0 && ifftY(m)<0)
%                 if (ifftY(m-1)==0)
%                     ifftYZeros(index)=timeifft(m-1);
%                 elseif (ifftY(m)==0)
%                     ifftYZeros(index)=timeifft(m);
%                 else
%                     ifftYZeros(index)=timeifft(m-1)+abs(ifftY(m-1))*(timeifft(m)-timeifft(m-1))/(abs(ifftY(m)-ifftY(m-1)));
%                 end
%                 index = index + 1;
%             end
%             if (timeifft(m)>1) %Só considera o primeiro segundo do movimento no domínio do tempo
%                 break
%             end
%         end
%         %Remover linhas que são nulas
%         ifftYZeros(:,~any(ifftYZeros,1)) = [];
%         ifftIndex = (1:length(ifftYZeros));
%         
%         %Preparar os vetores para ajuste da curva
%         ydata = ifftIndex;
%         xdata = ifftYZeros;
%         
%         %Lidar com dados ruins selecionados automaticamente: não cruzaram em
%         %zero...
%         if isempty(xdata)
%             xdata=0;
%         end
%         if isempty(ydata)
%             ydata=0;
%         end
%         
%         %-----------------
%         %Definir a função de 1o grau a ser ajustada nos pontos que cruzam o
%         %eixo das abscissas (zero-crossing points)
%         %-----------------
%         %Função do espectro analítico
%         funIFFT = @(x,xdata)x(1)*xdata+x(2);
%         %A função "fun" depende de dois parâmetros x1 e x2. x1 será igual ao
%         %dobro da frequência do sinal no modo considerado, pois em cada período
%         %há dois pontos que cruzam com o eixo
%         
%         %-----------------
%         %Ajuste da função analítica aos dados experimentais, por meio do método
%         %de levenberg-marquardt (mínimos quadrados)
%         %-----------------
%         %Vetor de ponto de início da função a ser ajustada: valores de x(i), i = 1 a 2
%         x0=[1,ydata(1)];
%         %Definição do método de ajuste
%         options = optimoptions('lsqcurvefit','Algorithm','levenberg-marquardt','Display','off');
%         lb = [];
%         ub = [];
%         %Obtenção dos parâmetros de ajuste da função.
%         x(:,i) = lsqcurvefit(funIFFT,x0,xdata,ydata,lb,ub,options);
%         
%         %-----------------
%         %Plotagem dos resultados. O parâmetro x(1) é igual ao dobro da
%         %frequência identificada
%         %-----------------
%         if plotaGraficosNessasRepeticoes(contadorDeArquivos) == 1
%             times = linspace(xdata(1),xdata(end));
%             xtemp = x(:,i);
%             ax = subplot(numPeaks,4,i+2+repeatition);
%             plot(ax,xdata,ydata,'b-',times,funIFFT(xtemp,times),'m-'); %Plotar o sinal original
%             str = {['Mode ', num2str(i)]};
%             str = join(str);
%             title(ax,{['Curve-fitting IFFT Method - ',char(str)]});
%             xlabel(ax,'Time (seconds)');
%             ylabel(ax,'Index (-)');
%             legend('Experimental data','Adjusted curve');
%             
%             str = {'\bfFitted equation: \rm',['y = \rm',num2str(x(1,i)),'x + (',num2str(x(2,i)),')'],['Frequency (Hz) = ',num2str(x(1,i)/2)]};
%             xlim([xdata(1) xdata(end)])
%             ylim([min(funIFFT(xtemp,times)) 1.25*max(max(funIFFT(xtemp,times)),max(ydata))])
%             %     xLim = xlim;
%             %     yLim = ylim;
%             t = text(0.45,0.12,str,'Units','normalized');
%             %     t = text(xLim(1)+0.05*(xLim(2)-xLim(1)),(yLim(1)+yLim(2))*0.7,str,'cyan');
%             t.EdgeColor = 'black';
%         end
%         
%         %Salva as frequências naturais obtidas no método da IFFT
%         NaturalFreqIFFT(i)=x(1,i)/2;
%         
%         %%
%         %-----------------
%         %APLICAÇÃO DO DECREMENTO LOGARÍTMICO
%         %Seleção dos picos no domínio do tempo para cálculo do decremento
%         %logarítmico. O ponto inicial considerado equivale ao maior pico, a
%         %partir do qual são tomados nPeaks picos subesquentes para cálculo do
%         %decremento
%         %-----------------
%         
%         yDecrement=abs(ifftY);
%         [rk, k]=findpeaks(yDecrement);
%         maxYdecrement=max(rk);
%         indexD = find(rk==maxYdecrement);
%         
%         
%         YdecrementFit=zeros(1,nPeaks);
%         XdecrementFit=zeros(1,nPeaks);
%         
%         aux=1;
%         if (indexD+nPeaks>length(rk))
%             nPeaks=length(rk)-indexD;
%         end
%         for p=indexD:indexD+nPeaks
%             YdecrementFit(aux)=rk(p);
%             XdecrementFit(aux)=aux;
%             aux=aux+1;
%         end
%         YdecrementFit(YdecrementFit==0) = [];
%         XdecrementFit(XdecrementFit==0) = [];
%         YdecrementFit=log(YdecrementFit);
%         
%         
%         %-----------------
%         %Definir a função de 1o grau a ser ajustada nos pontos que cruzam o
%         %eixo das abscissas (zero-crossing points)
%         %-----------------
%         %Função do espectro analítico
%         funDecrem = @(x,XdecrementFit)-x(1)*XdecrementFit/2+x(2);
%         %A função "fun" depende de dois parâmetros x1 e x2. x1 será igual ao
%         %dobro da frequência do sinal no modo considerado, pois em cada período
%         %há dois pontos que cruzam com o eixo
%         
%         %-----------------
%         %Ajuste da função analítica aos dados experimentais, por meio do método
%         %de levenberg-marquardt (mínimos quadrados)
%         %-----------------
%         %Vetor de ponto de início da função a ser ajustada: valores de x(i), i = 1 a 2
%         x0=[1,YdecrementFit(1)];
%         %Definição do método de ajuste
%         options = optimoptions('lsqcurvefit','Algorithm','levenberg-marquardt','Display','off');
%         lb = [];
%         ub = [];
%         %Obtenção dos parâmetros de ajuste da função.
%         x(:,i) = lsqcurvefit(funDecrem,x0,XdecrementFit,YdecrementFit,lb,ub,options);
%         
%         %-----------------
%         %Plotagem dos resultados. O parâmetro x(1) é igual ao dobro da
%         %frequência identificada
%         %-----------------
%         if plotaGraficosNessasRepeticoes(contadorDeArquivos) == 1
%             times = linspace(XdecrementFit(1),XdecrementFit(end));
%             xtemp = x(:,i);
%             ax = subplot(numPeaks,4,i+3+repeatition);
%             plot(ax,XdecrementFit,YdecrementFit,'b-',times,funDecrem(xtemp,times),'m-'); %Plotar o sinal original
%             str = {['Mode ', num2str(i)]};
%             str = join(str);
%             title(ax,{['Curve-fitting Logarithmic Decrement Method - ',char(str)]});
%             xlabel(ax,'Time (seconds)');
%             ylabel(ax,'ln|r_{k}|');
%             legend('Experimental data','Adjusted curve');
%         end
%         
%         %-----------------
%         %Calcula o decremento e a razão de amortecimento
%         %-----------------
%         decrement=x(1,i);
%         dampingRatio =100*decrement/((decrement*decrement+4*pi*pi)^0.5);
%         %funDecrement = @(x) x-decrement/((decrement*decrement-x*x)^2);    % function of x alone
%         %dampingRatio = fzero(funDecrement,0);
%         
%         
%         %str = {'\bfFitted equation: \rm',['ln|r_{k}| = \rm',num2str(x(1,i)),'x + (',num2str(x(2,i)),')'],['Decremento = ',num2str(decrement)],['\xi_{i}:',num2str(dampingRatio),' %']};
%         if plotaGraficosNessasRepeticoes(contadorDeArquivos) == 1
%             str = {'\bfResults: \rm',['Decremento = ',num2str(decrement)],['\xi_{i}:',num2str(dampingRatio),' %']};
%             xlim([XdecrementFit(1) XdecrementFit(end)])
%             ylim([min(funDecrem(xtemp,times)) max(YdecrementFit)])
%             xLim = xlim;
%             yLim = ylim;
%             t = text(0.05,0.15,str,'Units','normalized');
%             t.EdgeColor = 'black';
%         end
%         
%         repeatition = repeatition + 3;
%     end
    
    %     Código para organizar os vetores e saber qual é o pico mais alto. Mas
    %     isso já é feito na criação de NaturalFreq e NaturalFreqFFT, então não
    %     é necessario refazer aqui. Lá, o primeiro elemento (primeira
    %     frequência) já é a de maior pico.
    %     NaturalFreq=sortrows(NaturalFreq);
    %     NaturalFreqFFT=sortrows(NaturalFreqFFT);
    
    frequenciasObtidasPP(contadorDeArquivos,:)=NaturalFreq(:,2);
    %frequenciasObtidasIFFT(contadorDeArquivos,:)=NaturalFreqFFT(:,2);
    frequenciasObtidasIFFT(contadorDeArquivos,:)=NaturalFreqIFFT;
    maxAccel(contadorDeArquivos,1)=maximumAcceleration;
    rmsAccel(contadorDeArquivos,1)=rmsAcceleration;
    
    %Lê o cabeçalho do arquivo para armazenar a temperatura e o tempo de
    %amostragem
    fid = fopen(fullfile(path,file),'r');
    
    %Para Tubo 2, utilizar as opções abaixo:
    linenum = 3;
    
%     if contadorDeArquivos>primeiroArquivoMonstro-1 && contadorDeArquivos<ultimoArquivoMonstro+1
%         linenum = 4;
%         cabecalhoInfo = textscan(fid,'%s %f %s %s %f %s %s %s %s %s %s %s', 1, 'Delimiter',' ','headerlines',linenum-1);
%     else
        linenum = 3;
        cabecalhoInfo = textscan(fid,'%s %f %s %s %f %s %s %s %s %s %s %s', 1, 'Delimiter',' ','headerlines',linenum-1);
%     end
    
    temperaturaAmbiente(contadorDeArquivos) = cell2mat(cabecalhoInfo(1,2));
    %     instanteDeAmostragem(contadorDeArquivos) = cell2mat(cabecalhoInfo(1,5));
    
    %Handling do tempo considerando que o RTC clock está funcionando, e que
    %o tempo está sendo armazenado na forma "instant:xx:xx:xx", o que
    %envolve a dificuldade de remover a palavra "instant" do tempo
    %associado. Melhor seria que o RTC clock plotasse um espaço entre o
    %"instant" e o tempo, e, junto com as horas, minutos e segundos,
    %plotasse também a data do dia, no formato pronto para ser lido pelo
    %MATLAB.
    
    
    if contadorDeArquivos==primeiroArquivo %Se for a primeira amostra, inicializa o processo
        %InstanteDeAmostragem guarda apenas o intervalo de tempo em
        %segundos entre cada amostragem
        instanteDeAmostragem(contadorDeArquivos) = seconds(0);
        %Armazena a hora da primeira amostragem, para permitir o cálculo do
        %interalo de tempo para a segunda amostragem
        temporaryTime = (cabecalhoInfo(1,12)); %Vai ler o string "instant:xx:xx:xx", onde xx são os números do horário
        temporaryTime = split(temporaryTime{1},":"); %Para separarmos o "instant", que estará na primeira célula agora!
        lastTime = hours(str2double(temporaryTime{2}))+minutes(str2double(temporaryTime{3}))+seconds(str2double(temporaryTime{4}));
    else
        %Extrai a informação da hora da amostragem em questão, que será
        %comparada com a última hora gravada na variável lastTime.
        temporaryTime = (cabecalhoInfo(1,12)); %Vai ler o string "instant:xx:xx:xx", onde xx são os números do horário
        temporaryTime = split(temporaryTime{1},":"); %Para separarmos o "instant", que estará na primeira célula agora!
        presentTime = hours(str2double(temporaryTime{2}))+minutes(str2double(temporaryTime{3}))+seconds(str2double(temporaryTime{4}));
        %Teste se o presentTime é maior que lastTime, pois quando o vira a
        %noite para um novo dia, o presentTime se torna menor que o
        %lastTime, e a conta da diferença de tempo deve levar isso em
        %conta!
        
%         if contadorDeArquivos == 218
%             t=1;
%         end
        if presentTime<lastTime %se sim, o dia virou
            instanteDeAmostragem(contadorDeArquivos)=presentTime-lastTime+hours(24)+instanteDeAmostragem(contadorDeArquivos-1);
        else
            instanteDeAmostragem(contadorDeArquivos)=presentTime-lastTime+instanteDeAmostragem(contadorDeArquivos-1);
        end
        lastTime = presentTime; %Troca de bastões!
    end
        
    fclose(fid);
    
end

%%
%---------------------------------------------------------
%PLOTAGENS FINAIS
%---------------------------------------------------------
%Para a versão de Dezembro/2018 com ADXL 335, a plotagem das frequências
%foi:

% valorAberrante = 979;
% correcao = instanteDeAmostragem(valorAberrante)-instanteDeAmostragem(valorAberrante-1);
% correcao = correcao-(instanteDeAmostragem(valorAberrante-1)-instanteDeAmostragem(valorAberrante-2))
% instanteDeAmostragemConsertado=instanteDeAmostragem;
% for auxiliar=valorAberrante:length(instanteDeAmostragemConsertado)
% instanteDeAmostragemConsertado(auxiliar)=instanteDeAmostragemConsertado(auxiliar)-correcao;
% end
% tempo=(instanteDeAmostragemConsertado);
% 
% instanteDeAmostragem = instanteDeAmostragemConsertado;

tempo=(instanteDeAmostragem);
tempo.Format = 'dd:hh:mm:ss';
%plot(tempo+hours(17.5), sort(frequenciasObtidasPP,2))


disp("Max. acceleration:");
disp(maximumAcceleration);
disp("Max. RMS acceleration:");
disp(rmsAcceleration);

% Para o Tubo 2 (que tinha o ADXL335 e problema de ruído em 60Hz 240Hz), utilizar as opções abaixo:
% temp=sort(frequenciasObtidasPP,2);
% plot(tempo+hours(17.5), temp(:,1))
% hold on
% temp=sort(frequenciasObtidasIFFT,2);
% plot(tempo+hours(17.5), temp(:,1))
% legend("Peak Picking", "IFFT"); 

plot(tempo+hours(17.5), temperaturaAmbiente);
xlabel ("Idades (dd:hh:mm:ss)");
ylabel ("Temperatura ambiente (oC)");
title ("Temperatura ambiente durante o ensaio EMM-ARM");

%Para o Tubo 3, utilizar as opções abaixo:
% plot(tempo+hours(17.5), frequenciasObtidasPP(:,1))
% hold on
% plot(tempo+hours(17.5), frequenciasObtidasIFFT(:,1))
% legend("Peak Picking", "IFFT");

%Plota a evolução do módulo de elasticidade
figure
plot(tempo, frequenciasObtidasPP(:,1))
hold on

%Salva os resultados num arquivo TXT
instanteDeAmostragem.Format = 's';
% resultadosFinais = [char(instanteDeAmostragem), frequenciasObtidasPP];

fileID = fopen(nomeArquivoSalvamento,'wt');
% fileID = fopen('Apagueme.txt','wt');
for ii = 1:size(frequenciasObtidasPP,1)
    fprintf(fid,char(instanteDeAmostragem(ii)));
    fprintf(fid,'\t');
    fprintf(fid,'%20.18f',frequenciasObtidasPP(ii,1));
    fprintf(fid,'\t');
    fprintf(fid,'%20.18f',frequenciasObtidasPP(ii,2));
    fprintf(fid,'\t');
    fprintf(fid,'%20.18f',frequenciasObtidasPP(ii,3));
%     fprintf(fid,'%20.18f',rmsAccel(ii));
%     fprintf(fid,'\t');
%     fprintf(fid,'%20.18f',maxAccel(ii));
    fprintf(fid,'\n\r');
end
fclose(fid);

fileID = fopen(nomeArquivoSalvamento2,'wt');
% fileID = fopen('Apagueme.txt','wt');
for ii = 1:size(frequenciasObtidasPP,1)
    fprintf(fid,char(instanteDeAmostragem(ii)));
    fprintf(fid,'\t');
%     fprintf(fid,'%20.18f',frequenciasObtidasPP(ii));
    fprintf(fid,'%20.18f',rmsAccel(ii));
    fprintf(fid,'\t');
    fprintf(fid,'%20.18f',maxAccel(ii));
    fprintf(fid,'\n\r');
end
fclose(fid);

% fileID = fopen("ResultadosFinais_Sistema2_Temperatura.txt",'wt');
% % fileID = fopen('Apagueme.txt','wt');
% for ii = 1:size(temperaturaAmbiente)
%     fprintf(fid,char(instanteDeAmostragem(ii)));
%     fprintf(fid,'\t');
% %     fprintf(fid,'%20.18f',frequenciasObtidasPP(ii));
%     fprintf(fid,'%20.18f',temperaturaAmbiente(ii));
%     fprintf(fid,'\n\r');
% end
% fclose(fid);

% fprintf(fileID,'%16.8f %16.8f \n\r',resultadosFinais);
% fprintf(fileID,'%16.8f %16.8f \n\r',instanteDeAmostragem3, modElasMaterial);
% fclose(fileID);

toc

% load handel
load train
sound(y,Fs)