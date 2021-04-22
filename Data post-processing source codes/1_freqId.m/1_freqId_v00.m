%%---------------------------------------------------------
%INTRODU��O
%---------------------------------------------------------
% Este software usa fun��es do Signal Processing Toolbox
% OBSERVA��ES DA VERS�O
% Essa fun��o foi desenvolvida para o ensaio EMM-ARM com argamassa feito em
% Dezembro de 2018.
%
% Vers�o j� com as modifica��es incorporadas desde o teste de valida��o do
% algoritmo, previsto no plano de trabalho do projeto.
% As fun��es implementadas foram:
% 1 - Leitura dos dados; 
% 2 - Tratamento com filtro Butterworth (pode deixar op��es para ativar outros)
% 3 - C�lculo do PSD (normalizado ou n�o)
% 4 - Identifica��o modal (PP + HP e IFT) -
%   4.1 - verificar se o HP foi corrigido;
%   4.2 - verificar a validade de se fazer uma m�dia ponderada para escolher o pico;
% 5 - Reuni�o de todas as fun��es acima para ler uma pasta de resultados de ensaio EMM-ARM e
% plotar, ao final, todos os PSDs um ao lado do outro.
% 6 - Plotar tamb�m uma curva com apenas os picos
% 7 - Implementar o c�lculo do m�dulo de elasticidade a partir das frequ�ncias
% 8 - Plotar o m�dulo de elasticidade
%
% O arquivo de resultados dever� ser no formato de duas colunas, separadas por v�rgulas,
% sendo a primeira coluna referente �s acelera��es, em valores raw, e a segunda coluna
% referente aos instantes de amostragem, em microssegundos (10^-6 s)
%--------------------------------------------------------
% ESSA VERS�O TEM UM NOTCH FILTER IMPLEMENTADO.
% NESSA VERS�O, O FINDPEAKS DESPREZXA FREQU6�NCIAS ACIMA DA FREQU�NCIA DE
% CORTE

clear;
clc;

%%
%---------------------------------------------------------
%CONFIGURA��ES INICIAIS DO PROGRAMA
%---------------------------------------------------------
%%
%Define qual filtro ser� aplicado para a an�lise modal do sinal:
% 0: dados brutos;
% 1: filtro Butterworth
% 2: filtro Chebyshev
% 3: dados com decima��o e filtro Chebyshev
PreProcessAnaliseModal = 1;

nomeArquivoSalvamento = 'FREQUENCIAS-SIST1-0_3_REF.txt'; %Salva as frequ�ncias identificadas
nomeArquivoSalvamento2 = 'MAXRMSACCEL-SIST1-0_3_REF.txt'; %Salva as acelera��es m�xima e RMS
% nomeArquivoSalvamento2 = 'apagueme.txt';

% nomeArquivoSalvamento = 'apagueme.txt';
% nomeArquivoSalvamento2 = 'apagueme.txt';

 notchBottom = 0.1; %Frequ�ncia inferior do Notch Filter
 notchUpper = 0.5; %Frequ�ncia superior do Notch Filter
 firstNotchFilterFile=3000; %Arquivo a partir do qual ser� aplicado o primeiro Notch Filter
% notchBottom2 = 21.2; %Frequ�ncia inferior do Notch Filter
% notchUpper2 = 22.5; %Frequ�ncia superior do Notch Filter
% notchBottom3 = 4; %Frequ�ncia inferior do Notch Filter
% notchUpper3 = 5; %Frequ�ncia superior do Notch Filter

duracaoSoneca = 5; %Dura��o da soneca entre duas amostras, em minutos. Padr�o: 5 minutos.
desiredFs = 200;
normalized = false; %Define se os PSD utilizados s�o normalizados ou n�o.
scaleFactor = 1/2400; %Fator de escala que converte leituras do aceler�metro para g
fc = 40; %Defini��o da frequ�ncia de corte dos filtros (cut-off frequency)
fc_High = 10; %Defini��o da frequ�ncia de corte dos filtros (cut-off frequency)
numPeaks = 3; %At� qual frequ�ncia natural o algoritmo ir� procurar
ADCZero = 0; %Se o sensor for anal�gico com zero em 1.5V, � necess�rio
%centralizar os dados em torno da refer�ncia zero.
%PARA ADS1115 COM GANHO 4.096V:
% -ADXL 335: zero = 1.5V -> 12000 LSB
% -MMA 7361: zero = 1.65 V -> 13200 LSB
%Caso for digital, o valor de ADCZero = 0.
fontSize = 8; %Fontsize dos gr�ficos de time domain e PSD
plotWidth = 15;
plotHeight =8;

%Caixa de di�logo para defini��o dos headers dos arquivos de salvamento
% prompt = {'Insira nome do arquivo'};
% titulo = 'Input do usu�rio';
% dims = [1 35];
% definput = {'20','hsv'};
% fileName = char(inputdlg(prompt,titulo,dims,definput));

%Cria��o da vari�vel "null" a ser utilizada mais adiante
null = [];

%Defini��o da frequ�ncia m�xima nas plotagens ser� a frequ�ncia de corte dos filtros
freqMax = fc;
%freqMax = 100;
%Comente alguma das linhas acima para decidir como ser�o as plotagens
%

%Seleciona diret�rio dos resultados
[path] = uigetdir();

%Conta quandos arquivos de texto est�o no diret�rio
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
    %LEITURA, ARMAZENAMENTO E PLOTAGEM NO DOM�NIO DO TEMPO
    %---------------------------------------------------------
    %%
    %---------------------------------------------------------
    % Leitura do arquivo de dados
    %---------------------------------------------------------
    %Abre janela de di�logo para selec�o do arquivo de amostras a ser lido
    file = sprintf('%08d.txt', contadorDeArquivos) ;
    
    %Cria o endere�o da pasta utilizada para salvar os resultados
    savePath=strcat(path,'\');
    
    
    %% ESSA PARTE TEM QUE SER AJUSTADA PARA OS TUBOS 1 E 2, POIS DEPOIS DOS ARQUIVOS ORIGINADOS
    %% PELO ARQUIVO MONSTRO, O CABECALHO VOLTA A TER VALOR IGUAL A 6
%     if contadorDeArquivos<primeiroArquivoMonstro || contadorDeArquivos>ultimoArquivoMonstro
%         %Indica quantas linhas tem o cabe�alho de arquivo de resultados
%         cabecalho = 6;
%     else
        cabecalho = 6;
%     end
    
    %L� o arquivo com as amostragens. Wrapped entre fun��o try/catch para
    %pegar erros adivindos de arquivos ruins
    try
        M=csvread(fullfile(path,file),cabecalho); %Come�a pela primeira linha ap�s o cabe�alho
    catch exception
        M = 0;
    end
    
    
    
    %Come�a a ler a partir de uma coluna offset, ignorando cabe�alho do
    %arquivo, caso houver:
    %M=csvread(fullfile(path,file),7,0);
    
    %% TESTA SE O ARQUIVO N�O EST� VAZIO,
    %Se estiver, passar para o pr�ximo. Os registros desse arquivo s�o anulados
    
    %O tamanho do primeiro arquivo � tomado como refer�ncia de arquivo
    %"bom". Todos os demais s�o julgados com base nele
    
    if contadorDeArquivos == primeiroArquivo
        %Considera que um arquivo normal de amostragem produzir� um vetor M
        %entre 80% e 120% do primeiro arquivo considerado bom.
        tamanhoPadraoMin = 0.5*length(M);
        tamanhoPadraoMax = 1.2*length(M);
    elseif length(M)<tamanhoPadraoMin || length(M)>tamanhoPadraoMax %Arquivo ruim, pois est� zerado
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
    
    %Cria vetor para armazenar a dura��o de cada amostragem.
    % timeDiff = time;
    
    %As amostragens de tempo s�o feitas computando apenas o intervalo
    %entre duas medidas consecutivas. Abaixo, o vetor time passa a armazenar
    %o instante absoluto em que a amostra foi tomada
    for i=1:length(time)
        if i>1
            time(i)=time(i)+time(i-1);
        end
    end
    
    %Reamostra os dados para torn�-los uniformes!!! Isso � importante porque o
    %Arduino nem sempre toma medidas igualmente espa�adas (ainda mais em
    %frequ�ncias muito altas)
    % dummi=2;
    %     [accelRaw, time] = resample(accelRaw,time,desiredFs);
    
    %Seleciona s� parte dos vetores accelRaw e time, para evitar distor��es do
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
    
    fs=1/mean(nonzeros(abs(timeDiff)));%Frequ�ncia m�dia de amostragem, em Hz.
    
    %%
    %---------------------------------------------------------
    %Pr�-processamento do sinal
    %---------------------------------------------------------
    %Retirar a m�dia do sinal
    accelTemp = detrend(accelRaw);
    % accelTemp = accelRaw-1;
    
    
    % ------------------
    % BUTTERWORTH FILTER
    % Design a 8th order lowpass Butterworth filter with cutoff frequency of fc Hz.
    % Aparentemente esse filtro n�o afeta significativamente a an�lise no
    % dom�nio da frequ�ncia.
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
    % Aparentemente esse filtro n�o afeta significativamente a an�lise no
    % dom�nio da frequ�ncia.
%     chebOrder = 8;
%     dBpassband = 0.01;
%     [b,a] = cheby1(chebOrder,dBpassband,fc/(fs/2));
%     accelCheb = filter(b,a,accelTemp);
    
    % -----------------
    % DECIMA��O (reamostragem)
    % Rodrigues (2004): Fazer o processo de decima��o, que consiste na
    % reamostragem ou passagem das s�ries de resposta digitalizadas para uma
    % frequ�ncia de amostragem mais baixa. Para efectuar esta opera��o �
    % necess�rio filtrar as s�ries com um filtro passa-baixo com uma frequ�ncia
    % de corte de cerca de 0,4 da nova frequ�ncia de amostragem, para evitar
    % erros de aliasing nas s�ries decimadas.
%     r = round(fs/fc); %fator de decima��o
%     accelDec = decimate(accelTemp,r);
%     timeDec = decimate(time,r);
    %%
    %---------------------------------------------------------
    %Visualiza��o da resposta no tempo do sistema
    %---------------------------------------------------------
    
    if plotaGraficosNessasRepeticoes(contadorDeArquivos) == 1
        %Plota a amostragem no dom�nio do tempo
        ax1 = subplot(1,2,1); % top subplot
        
        %Retire os coment�rios abaixo para plotar os gr�ficos necess�rios
        %plot(ax1,time,accelRaw,'-b'); %Plot raw signal
        %hold on
        plot(ax1,time,accelBut,'-r'); %Plot filtered signal
        hold on
        %plot(ax1,time,accelCheb,'--g'); %Plot filtered signal
        %hold on
        %plot(ax1,timeDec,accelDec,'.k'); %Plot pre-processed signal
        
        %Configura��es da plotagem
        title(ax1,{'Acceleration signal','Time domain'});
        xlabel(ax1,'Time (seg)');
        ylabel(ax1,'Acceleration (g)');
        set(gca,'FontSize',fontSize)
        legend('Butterworth filtered', 'Chebyshev filtered', 'Decimated');
        
        %Permite inserir algum coment�rio na plotagem, no formato de uma caixa de
        %texto de dimens�es do vetor dim e conte�do da string str
        %dim = [0.6 0.25 0 0.1];
        %str = "Excita��o: 3 pux�es + 5 toques + 1/2 pux�es." + newline + "Amostragem a 700 Hz";
        %annotation('textbox',dim,'String',str,'FitBoxToText','on');
    end
    
    
    %%
    %---------------------------------------------------------
    % PLOTAGEM DO DFT, PSD E IDENTIFICA��O DOS PICOS - PEAK PICKING
    %---------------------------------------------------------
    %%
    %---------------------------------------------------------
    % Defini��o de qual sinal filtrado ser� utilizado de agora em diante
    %---------------------------------------------------------
    %Define qual filtro ser� aplicado para a an�lise modal do sinal:
    % 0: dados brutos;
    % 1: filtro Butterworth
    % 2: filtro Chebyshev
    % 3: dados com decima��o e filtro Chebyshev
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
            warning('Selecione um m�todo de pr�-processamento para a an�lise modal');
    end
%     %%
%     %---------------------------------------------------------
%     %C�lculo a DFT do sinal utilizando o algoritmo FFT
%     %---------------------------------------------------------
%     L = length(accel); %Comprimento da amostragem, isto �, o n�mero de pontos.
%     Y = fft(accel); %Calcula a DFT do sinal (� uma fun��o complexa)
%     P2 = abs(Y/L); %Obt�m somente o "one-sided spectrum" do sinal. Divide por L
%     %como um fator de escala, para normalizar a energia da fft
%     %em rela��o � quantidade de pontos utilizados no c�lculo
%     fftP1 = P2(1:(L/2+1)); %Obt�m apenas uma parte do "two-sided spectrum"
%     fftP1(2:end-1) = 2*fftP1(2:end-1); %Multiplica por dois para obter obter o "one-sided spectrum"
%     fftFreq = fs*(0:(L/2))/L; %Define o dom�nio- da frequ�ncia: as "bins"
%     %em que se calcula a frequ�ncia, ou a
%     %resolu��o do m�todo
%     %%
%     %---------------------------------------------------------
%     %Plotagem da FFT do sinal
%     %---------------------------------------------------------
%     % ax2 = subplot(3,1,2); % middle subplot
%     % plot(ax2,fftFreq,fftP1)
%     % title(ax2,'Single-Sided Amplitude Spectrum - FFT algorithm MATLAB')
%     % xlabel(ax2,'Frequency (Hz)')
%     % ylabel(ax2,'g (m/s^{2})') %A fun��o FFT no MATLAB retorna valores de amplitude com
%     %                           %unidades iguais �s do vetor de entrada: nesse caso, g.
%     % set(gca,'FontSize',10)
%     % xlim([0 freqMax])
%     % ylim([0 1.2*max(fftP1)])
%     % hold on;
%     
%     %Permite inserir algum coment�rio na plotagem, no formato de uma caixa de
%     %texto de dimens�es do vetor dim e conte�do da string str
%     %dim = [0.6 0.25 0 0.1];
%     %str = "Excita��o: 3 pux�es + 5 toques + 1/2 pux�es." + newline + "Amostragem a 700 Hz";
%     %annotation('textbox',dim,'String',str,'FitBoxToText','on');
%     %%
%     %---------------------------------------------------------
%     %M�todo Peak Picking aplicado ao FFT, para posterior plotagem
%     %---------------------------------------------------------
%     %Determina os pontos de pico do espectro de DFT e tenta relacion�-los �s
%     %frequ�ncias do sistema por compara��o dos picos.
%     %As seguintes suposi��es s�o feitas para lidar com o caso de picos muito
%     %pr�ximos devido a ru�dos do sistema:
%     %   1. Dois picos separados entre si de um valor menor que "threshold" (%)
%     %   da frequ�ncia relacionada ao pico n�o correspondem a picos distintos. O
%     %   ponto de menor densidade espectral de energia � descartado.
%     %   2. O c�digo considera apenas os "numFrequencia" picos mais altos, que
%     %   ser�o referentes �s "numFrequencia" primeiras frequ�ncias naturais do
%     %   sistema, onde "numFrequencia" � uma vari�vel definida pelo usu�rio.
%     %---------------------------------------------------------
%     
%     [peaks, freq] = findpeaks(fftP1,fftFreq);
%     threshold = 0.1; %Valor, em %, da faixa em torno de um pico que considera as frequ�ncias como iguais.
%     infLim = 1 - threshold;
%     supLim = 1 + threshold;
%     freq = freq.';
%     freq_peaksFFT = [freq peaks]; %Cria um vetor com frequ�ncias na primeira coluna
%     %e os picos na segunda
%     for i=1:length(freq)
%         for j=i+1:length(freq)
%             testedValue = freq_peaksFFT(i,1);
%             referenceValue = freq_peaksFFT(j,1);
%             %Checa se o valor de pico de �ndice j se refere � uma frequ�ncia
%             %pr�xima o suficiente da frequ�ncia do pico de �ndice i. Se sim,
%             %ambos os picos se referem � mesma frequ�ncia e devem ser
%             %considerados apenas uma vez.
%             if testedValue>infLim*referenceValue && testedValue<supLim*referenceValue
%                 %Aqui, apenas o pico com maior valor � considerado.
%                 if freq_peaksFFT(i,2)<freq_peaksFFT(j,2)
%                     freq_peaksFFT(i,2)=0;
%                     freq_peaksFFT(i,1)=0;
%                     %Elimina esses valores das pr�ximas checagens
%                 elseif freq_peaksFFT(i,2)>freq_peaksFFT(j,2)
%                     freq_peaksFFT(j,2)=0;
%                     freq_peaksFFT(j,1)=0;
%                     %Elimina esses valores das pr�ximas checagens
%                 end
%             else
%                 break
%             end
%         end
%     end
%     
%     %Parte do c�digo n�o debugada ainda
%     NaturalFreqFFT =sortrows(fliplr(freq_peaksFFT), 'descend');
%     list_of_lines_to_delete = numPeaks+1:1:length(NaturalFreqFFT);
%     NaturalFreqFFT(list_of_lines_to_delete,:) = [];
%     NaturalFreqFFT = sortrows(NaturalFreqFFT, 'descend');
    %%
    %---------------------------------------------------------
    %Plotagem dos picos identificados com PP sobre o gr�fico da DFT
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
    %C�lculo do PSD (power spectral density) do sinal utilizando o procedimento
    %de Welch (parti��o dos dados em v�rios conjuntos com sobreposi��o,
    %utiliza��o da fun��o janela de Hamming, e obten��o do PSD final a partir
    %da m�dia dos PSD de cada trecho).
    %---------------------------------------------------------
    
    % nfft = 2^nextpow2(length(accel)/2); %https://stackoverflow.com/questions/29439888/what-is-nfft-used-in-fft-function-in-matlab
    % [pxx, fWelch] = pwelch(accel, hann(nfft), nfft/2, nfft, fs); %https://stackoverflow.com/questions/22661758/how-to-improve-the-resolution-of-the-psd-using-matlab
    %  [pxx,fWelch] = pwelch(accel,null,null,[],fs); %Granja utiliza 16384 pontos para FFT - pg. 101
    [pxx,fWelch] = pwelch(accel,null,null,16384,fs); %Granja utiliza 16384 pontos para FFT - pg. 101
    %%
    %---------------------------------------------------------
    %Plotagem do PSD do sinal
    %--------------------------------------------------------
    %Define o t�tulo do gr�fico a depender se a op��o selecionada � normalizada
    %ou n�o
    
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
        
        %Instru��es de plotagem
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
    
    %Permite inserir algum coment�rio na plotagem, no formato de uma caixa de
    %texto de dimens�es do vetor dim e conte�do da string str
    %dim = [0.6 0.25 0 0.1];
    %str = "Excita��o: 3 pux�es + 5 toques + 1/2 pux�es." + newline + "Amostragem a 700 Hz";
    %annotation('textbox',dim,'String',str,'FitBoxToText','on');
    %%
    %---------------------------------------------------------
    %M�todo Peack-Picking aplicado ao PSD
    %---------------------------------------------------------
    %Determina os pontos de pico do PSD de Welch e tenta relacion�-los �s
    %frequ�ncias do sistema por compara��o dos picos.
    %As seguintes suposi��es s�o feitas para lidar com o caso de picos muito
    %pr�ximos devido a ru�dos do sistema:
    %   1. Dois picos separados entre si de um valor menor que "threshold" (%)
    %   da frequ�ncia relacionada ao pico n�o correspondem a picos distintos. O
    %   ponto de menor densidade espectral de energia � descartado.
    %   2. O c�digo considera apenas os "numFrequencia" picos mais altos, que
    %   ser�o referentes �s "numFrequencia" primeiras frequ�ncias naturais do
    %   sistema, onde "numFrequencia" � uma vari�vel definida pelo usu�rio.
    %---------------------------------------------------------
    
    cutLength = 2*round(length(pxx)*(fc/fs)); %Desprezar as frequ�ncias acima da frequ�ncia de corte fc
    [peaks, freq] = findpeaks(pxx(1:cutLength),fWelch(1:cutLength));
    threshold = 0.1; %Insert a threshold value in decimal form of a %
    infLim = 1 - threshold;
    supLim = 1 + threshold;
    numFrequencia = numPeaks; %Identificar apenas as "numFrequencia" primeiras frequ�ncias
    freq_peaks = [freq peaks]; %Create a vector with frequencies in the first
    %column and peaks in the second
    
    for i=1:length(freq)
        for j=i+1:length(freq)
            testedValue = freq_peaks(i,1);
            referenceValue = freq_peaks(j,1);
            %Checa se o valor de pico de �ndice j se refere � uma frequ�ncia
            %pr�xima o suficiente da frequ�ncia do pico de �ndice i. Se sim,
            %ambos os picos se referem � mesma frequ�ncia e devem ser
            %considerados apenas uma vez.
            if testedValue>infLim*referenceValue && testedValue<supLim*referenceValue
                %Aqui, apenas o pico com maior valor � considerado.
                if freq_peaks(i,2)<freq_peaks(j,2)
                    freq_peaks(i,2)=0;
                    freq_peaks(i,1)=0;
                    %Elimina esses valores das pr�ximas checagens
                elseif freq_peaks(i,2)>freq_peaks(j,2)
                    freq_peaks(j,2)=0;
                    freq_peaks(j,1)=0;
                    %Elimina esses valores das pr�ximas checagens
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
        %Salva as plotagens at� aqui (sinal no tempo e na frequ�ncia) no formato .fig e .emf
        %---------------------------------------------------------
        %set(gcf, 'units','pixels', 'Position', [0, 0, 1000, 1000]); %Ajusta  o tamanho da plotagem.
        tempName = '_Sinal no tempo e na frequ�ncia';
        saveName = strcat(fileName,tempName);
        saveas(gcf,fullfile(savePath,saveName),'fig');
        saveas(gcf,fullfile(savePath,saveName),'emf');
    end
    
    
%     %%
%     %---------------------------------------------------------
%     % DETERMINA��O DO AMORTECIMENTO PELO M�TODO DA MEIA POT�NCIA
%     %---------------------------------------------------------
%     %%
%     %---------------------------------------------------------
%     %Esse m�todo � baseado em Rodrigues (2004), pg 131 e em
%     %Granja (2016), pg 102.
%     % Pode-se utilizar m�todos de interpola��o para os pontos de meia pot�ncia,
%     % segundo Rodrigues (2004):
%     % 1 - interpola��o linear
%     % 2 - ajuste de uma par�bola aos tr�s pontos de maior amplitude
%     % 3 - ajuste de uma spline em torno dos valores de pico
%     %Nesse c�digo � utilizada uma interpola��o linear
%     %---------------------------------------------------------
%     dampHalfPower=zeros(numPeaks,1);
%     deltaWelch = fWelch(2)-fWelch(1);%Diferen�a entre dois elementos de fWelch
%     deltaF = 1; %Varia��o em torno do pico em estudo que define o trecho ajustado
%     thresholdIndex = round(deltaF/deltaWelch); %Varia��o +- deltaF em termos de �ndices de fWelch
%     
%     if plotaGraficosNessasRepeticoes(contadorDeArquivos) == 1
%         fig2 = figure;
%     end
%     
%     for i=1:numPeaks
%         %-----------------
%         %Selecionar a parte do PSD correspondente � i-th frequ�ncia que ser�
%         %utilizada no ajuste.
%         %-----------------
%         %�ndice em fWelch do pico em an�lise
%         index = find(fWelch==NaturalFreq(i,2),1);
%         %Determina a pot�ncia no pico do PSD
%         potMax = pxx(index);
%         %Determina a frequ�ncia no pico do PSD
%         freqMax = fWelch(index);
%         
%         %Procura, � esquerda do pico, o primeiro ponto cuja a pot�ncia seja
%         %menor que a metade da pot�ncia de pico
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
%                 spotEsq = 1; %Na mosca! Exatamente a pot�ncia m�dia!
%                 break
%             end
%         end
%         
%         %Procura, � direita do pico, o primeiro ponto cuja a pot�ncia seja
%         %menor que a metade da pot�ncia de pico
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
%                 spotDir = 1; %Na mosca! Exatamente a pot�ncia m�dia!
%                 break
%             end
%         end
%         
%         %Se as frequ�ncias encontradas anteriormente n�o corresponderem
%         %a pot�ncias exatamente iguais a metade da pot�ncia de pico, efetuar
%         %uma inteporla��o linear com os valores das s�ries de amostras
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
%         %C�lculo do coeficiente de amortecimento pelo m�todo da meia pot�ncia
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
%             %Plota o espectro de pot�ncia
%             plot(ax,xdata,ydata,'ro-','MarkerSize', 5);
%             hold on;
%             %Obt�m os limites do gr�fico para ajustes posteriores
%             xlim([xdata(1) xdata(end)])
%             ylim([min(ydata) 1.25*max(ydata)])
%             xLim = xlim; %Vetor com os valores limites de x no gr�fico
%             yLim = ylim; %Vetor com os valores limites de y no gr�fico
%             %Plota os pontos de meia pot�ncia utilizados no c�lculo do coeficiente
%             %de amortecimento
%             plot (freqMax,potMax, 'sb', 'MarkerSize', 8,'MarkerFaceColor','b');
%             plot (w1,p1, 'sb', 'MarkerSize', 8,'MarkerFaceColor','b');
%             plot (w2,p2, 'sb', 'MarkerSize', 8,'MarkerFaceColor','b');
%             hold on;
%             %Acrescenta as frequ�ncias e pot�ncias relativas aos pontos marcados
%             str = {'\omega_{peak}'};
%             text(freqMax, potMax+0.075*yLim(2), str, 'FontSize', fontSize);
%             str = {'\omega_1'};
%             text(w1-0.015*(xLim(2)-xLim(1)), p1+0.075*yLim(2), str, 'FontSize', fontSize);
%             str = {'\omega_2'};
%             text(w2, p2+0.075*yLim(2), str, 'FontSize', fontSize);
%             %Desenha uma linha para marcar os pontos utilizados para c�lculo do
%             %amortecimento
%             grayAlpha = 0.5; %Define o tom de cinza da linha (mais claro quanto
%             %mais pr�ximo de 1
%             line([xLim(1);w1],[p1;p1],'linestyle','--','color',[0,0,0]+grayAlpha);
%             line([w1;w1],[yLim(1);p1],'linestyle','--','color',[0,0,0]+grayAlpha);
%             line([xLim(1);w2],[p2;p2],'linestyle','--','color',[0,0,0]+grayAlpha);
%             line([w2;w2],[yLim(1);p2],'linestyle','--','color',[0,0,0]+grayAlpha);
%             %Insere t�tulos, legenda, identifica��o dos eixos, e caixa de texto com
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
%     %Salva as plotagens at� aqui (par�metros modais pela meia pot�ncia) no formato .fig e .emf
%     %---------------------------------------------------------
%     if plotaGraficosNessasRepeticoes(contadorDeArquivos) == 1
%         %Ajusta  o tamanho da plotagem.
%         set(gcf, 'units','centimeters', 'Position', [0, 0, plotWidth, plotHeight]);
%         %set(gcf, 'units','pixels', 'Position', [0, 0, 1000, 1000]); %Ajusta  o tamanho da plotagem.
%         tempName = '_Par�metros modais - Meia Pot�ncia';
%         saveName = strcat(fileName,tempName);
%         saveas(gcf,fullfile(savePath,saveName),'fig');
%         saveas(gcf,fullfile(savePath,saveName),'emf');
%     end
%     
%     
    %%
    %---------------------------------------------------------
    % DETERMINA��O DO AMORTECIMENTO PELO AJUSTE DO ESPECTRO ANAL�TICO
    %---------------------------------------------------------
    %%
    %---------------------------------------------------------
    %Determina��o dos par�metros modais pelo ajuste do espectro
    %anal�ico de um sistema de 1 GL
    %Esse m�todo � baseado em Rodrigues (2004), pg 132
    %---------------------------------------------------------
    % %Vetor com os par�metros anal�ticos a serem ajustados
    % x=zeros(4,numPeaks);
    % deltaWelch = fWelch(2)-fWelch(1);%Diferen�a entre dois elementos de fWelch
    % deltaF = 0.5; %Varia��o em torno do pico em estudo que define o trecho ajustado
    % thresholdIndex = round(deltaF/deltaWelch); %Varia��o +- deltaF em termos de �ndices de fWelch
    % fig3 = figure;
    %
    % for i=1:numPeaks
    %     %-----------------
    %     %Selecionar a parte do SPD correspondente � i-th frequ�ncia que ser�
    %     %utilizada no ajuste.
    %     %-----------------
    %     %�ndice em fWelch do pico em an�lise
    %     index = find(fWelch==NaturalFreq(i,2),1);
    %     %Define a parte do SPD a ser ajustada pelos par�metros
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
    %     %Definir a fun��o anal�tica que descreve a resposta em frequ�ncia de
    %     %um sistema de 1 GL que ser� ajustada ao trecho em an�lise
    %     %-----------------
    %     %Fun��o do espectro anal�tico
    %     fun = @(x,xdata)x(1)*((abs(((xdata*2*pi).^2)./(1-((xdata*2*pi/(2*pi*x(2))).^2)+1j*2*x(3)*(2*pi*xdata/(2*pi*x(2)))))).^2)+x(4);
    %     %A fun��o "fun" depende de quatro par�metros x1, x2, x3, x4. A
    %     %correspond�ncia desses par�metros �s vari�veis modais pode ser feita
    %     %checando Rodrigues (2004), pg 132.
    %
    %     %-----------------
    %     %Ajuste da fun��o anal�tica aos dados experimentais, por meio do m�todo
    %     %de levenberg-marquardt (m�nimos quadrados)
    %     %-----------------
    %     %Ponto de in�cio da fun��o a ser ajustada: valores de x(i), i = 1 a 4
    %     x0=[pxx(1)/10^6,fWelch(index),dampHalfPower(i),(ydata(1)+ydata(m-1))/2];
    %     %Defini��o do m�todo de ajuste
    %     options = optimoptions('lsqcurvefit','Algorithm','levenberg-marquardt');
    %     lb = [];
    %     ub = [];
    %     %Obten��o dos par�metros de ajuste da fun��o.
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
    % %Salva as plotagens at� aqui (par�metros modais por ajuste do espectro anal�tico) no formato .fig e .emf
    % %---------------------------------------------------------
    % %set(gcf, 'units','pixels', 'Position', [0, 0, 1000, 1000]); %Ajusta  o tamanho da plotagem.
    % tempName = '_Par�metros modais - Espectro anal�tico';
    % saveName = strcat(fileName,tempName);
    % saveas(gcf,fullfile(savePath,saveName),'fig');
    % saveas(gcf,fullfile(savePath,saveName),'emf');
    %
    
    
%     %%
%     %---------------------------------------------------------
%     % M�TODO IFT DE AN�LISE MODAL
%     %---------------------------------------------------------
%     %%
%     %---------------------------------------------------------
%     %C�lculo da FFT do sinal, utilizada para transposi��o do dom�nio da
%     %frequ�ncia para tempo
%     %---------------------------------------------------------
%     fftY=fft(accel);
%     FfftY=linspace(-1,1,L)*fs/2;
%     %Calcula o espectro one-sided, utilizado em plotagens
%     P2 = abs(fftY/L);
%     fftYoS = P2(1:(L/2+1)); %Obt�m apenas uma parte do "two-sided spectrum"
%     fftYoS(2:end-1) = 2*fftYoS(2:end-1); %Multiplica por dois para obter obter o "one-sided spectrum"
%     FfftYoS = fs*(0:(L/2))/L; %Define o dom�nio da frequ�ncia: as "bins"
%     %em que se calcula a frequ�ncia, ou a
%     %resolu��o do m�todo
%     %Calcula uma vers�o "normalizada" do vetor da FFT do sinal, mais f�cil de
%     %plotar para debugar
%     fftY_norm=[fftY(floor((L/2))+2:L); fftY(1:floor((L/2))+1)];
%     halfFFT=L-(L/2)+2;
%     %Plota para debug
%     %fig3 = figure;
%     %plot(FfftY,2*abs(fftY_norm));
%     %%
%     %---------------------------------------------------------
%     %M�todo IFFT: sele��o de regi�es do FFT, a partir dos picos identificados
%     %no PSD, e transposi��o para o dom�nio do tempo, no qual a frequ�ncia e o
%     %coeficiente de amortecimento s�o calculados com base n
%     %---------------------------------------------------------
%     x=zeros(2,numPeaks); %Vetor com os par�metros da curva a serem ajustados para determina��o da
%     %frequ�ncia natural
%     deltaWelch = FfftY(2)-FfftY(1);%Diferen�a entre dois elementos de fWelch
%     deltaF = 2; %Varia��o em torno do pico em estudo que ter� ganho 1
%     deltaFgauss = 2; %Tamanho da cauda da fun��o gaussiana, desde a extremidade da fun��o retangular, de ganho 1, at� o ponto de ganho redPercent
%     redPercent = 0.01; %Redu��o desejada no filtro gaussiano, em %, na extremidade igual � deltaFgauss/2
%     nPeaks = 100; %Quantidade de picos a serem utilizados para ajuste do decremento.
%     thresholdIndex = round(deltaF/deltaWelch); %Varia��o +- deltaF em termos de �ndices de fWelch
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
%         %SELE��O DO TRECHO DO FFT
%         %Selecionar a parte do FFT correspondente � i-th frequ�ncia que ser�
%         %utilizada na identifica��o modal no dom�nio do tempo.
%         %-----------------
%         
%         %Determina��o do indice no vetor de frequ�ncias do FFT relativo ao pico em an�lise:
%         %Como o pico foi calculado a partir do PSD, a correspond�ncia n�o �
%         %exata e deve ser calculada como a melhor aproxima��o poss�vel
%         goal=NaturalFreq(i,2);
%         dist = abs(FfftY - goal);
%         minDist = min(dist((round(length(FfftY)/2):end)));
%         index = (dist == minDist); %Ao inv�s de usar a fun��o find, usa �ndices l�gicos (recomenda��o do MATLAB)
%         
%         %Define a parte do FFT a ser utilizada na identifica��o modal
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
%         %Seleciona a parte do fftY necess�rio
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
%         %Ajusta o ydataPart para se referir a fftY e n�o a fftY_norm
%         ydataPart = [ydataPart(floor(L/2)+1:end) ydataPart(1:floor(L/2))];
%         ifftY = (ifft(ydataPart,'symmetric'));
%         timeifft=time;
%         
%         if plotaGraficosNessasRepeticoes(contadorDeArquivos) == 1
%             %Plota o sinal no tempo ap�s ifft
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
%         %IDENTIFICA��O MODAL DA FREQU�NCIA
%         %Investiga quais os pontos passam por zero para determina��o da
%         %frequ�ncia
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
%             if (timeifft(m)>1) %S� considera o primeiro segundo do movimento no dom�nio do tempo
%                 break
%             end
%         end
%         %Remover linhas que s�o nulas
%         ifftYZeros(:,~any(ifftYZeros,1)) = [];
%         ifftIndex = (1:length(ifftYZeros));
%         
%         %Preparar os vetores para ajuste da curva
%         ydata = ifftIndex;
%         xdata = ifftYZeros;
%         
%         %Lidar com dados ruins selecionados automaticamente: n�o cruzaram em
%         %zero...
%         if isempty(xdata)
%             xdata=0;
%         end
%         if isempty(ydata)
%             ydata=0;
%         end
%         
%         %-----------------
%         %Definir a fun��o de 1o grau a ser ajustada nos pontos que cruzam o
%         %eixo das abscissas (zero-crossing points)
%         %-----------------
%         %Fun��o do espectro anal�tico
%         funIFFT = @(x,xdata)x(1)*xdata+x(2);
%         %A fun��o "fun" depende de dois par�metros x1 e x2. x1 ser� igual ao
%         %dobro da frequ�ncia do sinal no modo considerado, pois em cada per�odo
%         %h� dois pontos que cruzam com o eixo
%         
%         %-----------------
%         %Ajuste da fun��o anal�tica aos dados experimentais, por meio do m�todo
%         %de levenberg-marquardt (m�nimos quadrados)
%         %-----------------
%         %Vetor de ponto de in�cio da fun��o a ser ajustada: valores de x(i), i = 1 a 2
%         x0=[1,ydata(1)];
%         %Defini��o do m�todo de ajuste
%         options = optimoptions('lsqcurvefit','Algorithm','levenberg-marquardt','Display','off');
%         lb = [];
%         ub = [];
%         %Obten��o dos par�metros de ajuste da fun��o.
%         x(:,i) = lsqcurvefit(funIFFT,x0,xdata,ydata,lb,ub,options);
%         
%         %-----------------
%         %Plotagem dos resultados. O par�metro x(1) � igual ao dobro da
%         %frequ�ncia identificada
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
%         %Salva as frequ�ncias naturais obtidas no m�todo da IFFT
%         NaturalFreqIFFT(i)=x(1,i)/2;
%         
%         %%
%         %-----------------
%         %APLICA��O DO DECREMENTO LOGAR�TMICO
%         %Sele��o dos picos no dom�nio do tempo para c�lculo do decremento
%         %logar�tmico. O ponto inicial considerado equivale ao maior pico, a
%         %partir do qual s�o tomados nPeaks picos subesquentes para c�lculo do
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
%         %Definir a fun��o de 1o grau a ser ajustada nos pontos que cruzam o
%         %eixo das abscissas (zero-crossing points)
%         %-----------------
%         %Fun��o do espectro anal�tico
%         funDecrem = @(x,XdecrementFit)-x(1)*XdecrementFit/2+x(2);
%         %A fun��o "fun" depende de dois par�metros x1 e x2. x1 ser� igual ao
%         %dobro da frequ�ncia do sinal no modo considerado, pois em cada per�odo
%         %h� dois pontos que cruzam com o eixo
%         
%         %-----------------
%         %Ajuste da fun��o anal�tica aos dados experimentais, por meio do m�todo
%         %de levenberg-marquardt (m�nimos quadrados)
%         %-----------------
%         %Vetor de ponto de in�cio da fun��o a ser ajustada: valores de x(i), i = 1 a 2
%         x0=[1,YdecrementFit(1)];
%         %Defini��o do m�todo de ajuste
%         options = optimoptions('lsqcurvefit','Algorithm','levenberg-marquardt','Display','off');
%         lb = [];
%         ub = [];
%         %Obten��o dos par�metros de ajuste da fun��o.
%         x(:,i) = lsqcurvefit(funDecrem,x0,XdecrementFit,YdecrementFit,lb,ub,options);
%         
%         %-----------------
%         %Plotagem dos resultados. O par�metro x(1) � igual ao dobro da
%         %frequ�ncia identificada
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
%         %Calcula o decremento e a raz�o de amortecimento
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
    
    %     C�digo para organizar os vetores e saber qual � o pico mais alto. Mas
    %     isso j� � feito na cria��o de NaturalFreq e NaturalFreqFFT, ent�o n�o
    %     � necessario refazer aqui. L�, o primeiro elemento (primeira
    %     frequ�ncia) j� � a de maior pico.
    %     NaturalFreq=sortrows(NaturalFreq);
    %     NaturalFreqFFT=sortrows(NaturalFreqFFT);
    
    frequenciasObtidasPP(contadorDeArquivos,:)=NaturalFreq(:,2);
    %frequenciasObtidasIFFT(contadorDeArquivos,:)=NaturalFreqFFT(:,2);
    frequenciasObtidasIFFT(contadorDeArquivos,:)=NaturalFreqIFFT;
    maxAccel(contadorDeArquivos,1)=maximumAcceleration;
    rmsAccel(contadorDeArquivos,1)=rmsAcceleration;
    
    %L� o cabe�alho do arquivo para armazenar a temperatura e o tempo de
    %amostragem
    fid = fopen(fullfile(path,file),'r');
    
    %Para Tubo 2, utilizar as op��es abaixo:
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
    
    %Handling do tempo considerando que o RTC clock est� funcionando, e que
    %o tempo est� sendo armazenado na forma "instant:xx:xx:xx", o que
    %envolve a dificuldade de remover a palavra "instant" do tempo
    %associado. Melhor seria que o RTC clock plotasse um espa�o entre o
    %"instant" e o tempo, e, junto com as horas, minutos e segundos,
    %plotasse tamb�m a data do dia, no formato pronto para ser lido pelo
    %MATLAB.
    
    
    if contadorDeArquivos==primeiroArquivo %Se for a primeira amostra, inicializa o processo
        %InstanteDeAmostragem guarda apenas o intervalo de tempo em
        %segundos entre cada amostragem
        instanteDeAmostragem(contadorDeArquivos) = seconds(0);
        %Armazena a hora da primeira amostragem, para permitir o c�lculo do
        %interalo de tempo para a segunda amostragem
        temporaryTime = (cabecalhoInfo(1,12)); %Vai ler o string "instant:xx:xx:xx", onde xx s�o os n�meros do hor�rio
        temporaryTime = split(temporaryTime{1},":"); %Para separarmos o "instant", que estar� na primeira c�lula agora!
        lastTime = hours(str2double(temporaryTime{2}))+minutes(str2double(temporaryTime{3}))+seconds(str2double(temporaryTime{4}));
    else
        %Extrai a informa��o da hora da amostragem em quest�o, que ser�
        %comparada com a �ltima hora gravada na vari�vel lastTime.
        temporaryTime = (cabecalhoInfo(1,12)); %Vai ler o string "instant:xx:xx:xx", onde xx s�o os n�meros do hor�rio
        temporaryTime = split(temporaryTime{1},":"); %Para separarmos o "instant", que estar� na primeira c�lula agora!
        presentTime = hours(str2double(temporaryTime{2}))+minutes(str2double(temporaryTime{3}))+seconds(str2double(temporaryTime{4}));
        %Teste se o presentTime � maior que lastTime, pois quando o vira a
        %noite para um novo dia, o presentTime se torna menor que o
        %lastTime, e a conta da diferen�a de tempo deve levar isso em
        %conta!
        
%         if contadorDeArquivos == 218
%             t=1;
%         end
        if presentTime<lastTime %se sim, o dia virou
            instanteDeAmostragem(contadorDeArquivos)=presentTime-lastTime+hours(24)+instanteDeAmostragem(contadorDeArquivos-1);
        else
            instanteDeAmostragem(contadorDeArquivos)=presentTime-lastTime+instanteDeAmostragem(contadorDeArquivos-1);
        end
        lastTime = presentTime; %Troca de bast�es!
    end
        
    fclose(fid);
    
end

%%
%---------------------------------------------------------
%PLOTAGENS FINAIS
%---------------------------------------------------------
%Para a vers�o de Dezembro/2018 com ADXL 335, a plotagem das frequ�ncias
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

% Para o Tubo 2 (que tinha o ADXL335 e problema de ru�do em 60Hz 240Hz), utilizar as op��es abaixo:
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

%Para o Tubo 3, utilizar as op��es abaixo:
% plot(tempo+hours(17.5), frequenciasObtidasPP(:,1))
% hold on
% plot(tempo+hours(17.5), frequenciasObtidasIFFT(:,1))
% legend("Peak Picking", "IFFT");

%Plota a evolu��o do m�dulo de elasticidade
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