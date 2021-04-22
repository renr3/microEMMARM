%%
%VERSÃO: Visualização dos resultados parciais do sistema 2

%%---------------------------------------------------------
%CÁLCULO DO MÓDULO DE ELASTICIDADE
%---------------------------------------------------------
%Assume que a frequência utilizada é asempre a primeira frequência do modo
%de flexão
% clc;
clear all

i = 1;

figure;
numTubo = 4; %Quantidade de tubos
markerSize=80;
fontSize=18;
lgdFontSize=16;


%% DEFINIÇÕES INICIAIS

%Nome dos resultados:
NomeDoArquivo = ["FREQUENCIAS-SIST2-0_4_REF.txt" "FREQUENCIAS-SIST3-0_4_REF.txt"...
    "FREQUENCIAS-SIST1-0_3_REF.txt" "FREQUENCIAS-SIST4-0_3_REF.txt"];
NomeDoArquivoSalvamento = ["MODELAS-SIST2-0_4_REF.txt" "MODELAS-SIST3-0_4_REF.txt"...
    "MODELAS-SIST1-0_3_REF.txt" "MODELAS-SIST4-0_3_REF.txt"];

color=[[0 0 1];[0 1 1];[1 0 1];[1 0 0]];
markerType=["o" "s" "d" "^"];

%CHECAR VÃOS, DEVEM LEVAR A MÓDULOS DE ELASTICIDADE COMPATÍVEIS
comprimentoLivre = [0.46 0.4665 0.456 0.454];
comprimentoCompleto = [0.545 0.551 0.545 0.545];
comprimentoLivreEmVazio = [0.45 0.45 0.45 0.45];

%Dimensões do tubo
espessuraParede = 0.0019; %Em m, medição com paquímetro
diametroExterno = 0.0254; %Em m, medição com paquímetro

%Massa do material cimentício
% densidadeMaterial = [1887 1887 1798 1798]; %Em kg/m3, ensaiado segundo ABNT NBR 1.....
densidadeMaterial = [1953.78 1953.78 1973.73 1973.73]; %Em kg/m3, ensaiado segundo ABNT NBR 1....

%Freqências em vazio
frequenciaEmVazioTubo = [30.620 30.574 30.6616 30.569];
massaTubo = [103.73 105.19 103.73 104.08];
mTampa = 0.010;
mAceler = 0.005;
mPontaVazio = 0.00; %Massa no instante em que o ensaio em vazio foi realizado

plotInLog = "Não";

%% PLOTAGEM DOS RESULTADOS DOS TUBOS
for i=1:numTubo
    fileID = fopen(NomeDoArquivo(i),'r');
    
    formatSpec = '%f %s %f %f %f';
    sizeResultados = [7 Inf];
    resultados = fscanf(fileID,formatSpec,sizeResultados);
    resultados = resultados.';
    
    %Obtem as frequências e os instantes de medição a partir dos resultados
    instanteDeAmostragem = resultados(:,1);
    frequenciasObtidasPP = resultados(:,5);
    
    %Cálculo do módulo
    %Propriedades do tubo
    diametroInterno = (diametroExterno-2*espessuraParede); %Em m, medição com paquímetro
    inerciaPVC = pi*((diametroExterno^4)-(diametroInterno^4))/64;    
    comprimento = comprimentoLivre(i); %Em m
    %Massa do tubo e massa concentrada
    mPVC = comprimentoLivre(i)*(massaTubo(i)/1000)/comprimentoCompleto(i); %Massa do PVC, em kg, só do vão livre
    mPonta = mTampa + mAceler;
    mPVCVerific(i) = mPVC;
    
    %Ensaio em vazio para determinação do módulo de elasticidade
    comprimentoEmVazio = comprimentoLivreEmVazio(i);
    mPVCemVazio = comprimentoEmVazio*(massaTubo(i)/1000)/comprimentoCompleto(i); %Massa do PVC, em kg, só do vão livre, durante o ensaio em vazio
    frequenciaEmVazio = frequenciaEmVazioTubo(i); %Frequência do tubo vazio
    modElasPVC = (comprimentoEmVazio^3)*(mPontaVazio+0.24*mPVCemVazio)*((frequenciaEmVazio*2*pi)^2)/(3*inerciaPVC); %Em Pa, do ensaio com tubo vazio
    modElasPVCVerif(i)=modElasPVC;
    
    %Propriedades de massa e geometria do material ensaiado
    mMaterial = (diametroInterno*diametroInterno/4)*pi*densidadeMaterial(i)*comprimento; %Em kg
    inerciaMaterial = pi*(diametroInterno^4)/64;
    mPastaVerif(i)=mMaterial;
    
    %Propriedades da seção compósita
    mMaterial = mMaterial + mPVC;          
    mMaterialCompletoVerif(i) = mMaterial*comprimentoCompleto(i)/comprimento; %Massa do tubo inteiro, para comparar com pesagens posteriores
    mMaterialLivreVerif(i)=mMaterial;
    mLVerif(i)=mPVC/comprimento;
    
    %Cálculo do módulo de elasticidade da seção compósita
    modElasInerciaCompos = (comprimento^3)*(mPonta+0.24*mMaterial).*((frequenciasObtidasPP(:,1).*2*pi).^2)./3;
    initialguess = modElasInerciaCompos;   
    for k=1:length(frequenciasObtidasPP(:,1))
        omega=2*pi*frequenciasObtidasPP(k,1);
        L=comprimento; %Comprimento livre, em vibração
        mL = mMaterial/comprimento; %Massa linear do tubo compósito
        mLVerif(i)=mL;
        mP = mPonta;
        %         a = (((omega.^2).*mL./EI).^(1/4));
        myFunction = @(EI,omega,L,mL,mP) ((((omega.^2).*mL./EI).^(1/4))^3)*(cosh((((omega.^2).*mL./EI).^(1/4))*L)...
            *cos((((omega.^2).*mL./EI).^(1/4))*L)+1)+(omega*omega*mP/EI)*(cos((((omega.^2).*mL./EI).^(1/4))*L)...
            *sinh((((omega.^2).*mL./EI).^(1/4))*L)-cosh((((omega.^2).*mL./EI).^(1/4))*L)*sin((((omega.^2).*mL./EI).^(1/4))*L));
        transcendental = @(EI) myFunction(EI,omega,L,mL,mP); %Equação transcendental a ser resolvida, em função apenas de EI (mod.elást. e inércia da seção compósita)
        if initialguess(k)==0
            initialguess(k)=initialguess(k-1);
        end
        modElasInerciaComposPrecise(k,1) = fzero(transcendental,initialguess(k));
    end
    %Cálculo do módulo de elasticidade do material, utilizando a hipótese de seção perfeitamente compósita   
    modElasMaterial = (modElasInerciaComposPrecise-modElasPVC*inerciaPVC)./inerciaMaterial;

    %Ajuste do tempo para considerar o início do ensaio após o instante t0
    tempo = (57/(24*60))+(instanteDeAmostragem)/(60*60*24);
    %Zerar os valores iniciais durante a dormência
%     modElasMaterial = -1000000000*0.31+modElasMaterial; 
            
    %Salva o arquivo de resutlados
    nomeArquivoSalvamento = sprintf(NomeDoArquivoSalvamento(i));
    fileID = fopen(nomeArquivoSalvamento,'wt');
%     aux=1;
%     for ii = 1:size(modElasMaterial)
%         if tempo(aux)<=0.0925
%             tempo(aux)=[];
%             modElasMaterial(aux)=[];
%             aux=aux-1;
%         end
%         aux=aux+1;
%     end
%     
    mean=0;
    aux=0;
    for ii = 1:size(modElasMaterial)
        if tempo(ii)<=0.19
            mean=mean+modElasMaterial(ii);
            aux=aux+1;
        end
    end
    modElasMaterial=modElasMaterial-mean/aux;
    
        
    for ii = 1:size(modElasMaterial)
        fprintf(fileID,'%20.18f',tempo(ii));
        fprintf(fileID,'\t');
        fprintf(fileID,'%20.18f',modElasMaterial(ii));
        fprintf(fileID,'\n\r');
    end
    fclose(fileID);
    
        %Plotagem
    scatter(tempo, modElasMaterial/1000000000,markerSize,'k', markerType(i),'MarkerFaceColor', color(i,:));
    hold on
    
    %Zera estas variáveis para a próxima iteração
    modElasInerciaComposPrecise=0;
    modElasInerciaCompos=0;
end


%% Legendas e resultados de referência

%Plotagem dos resultados obtidos por frequência ressonante e compressão clássica

% hold on
% plot(tempoResonantFrequency, modElasResonantFrequency,'*k');
% errorbar(tempoResonantFrequency, modElasResonantFrequency, modElasResonantFrequency_Err,'k', 'LineStyle','none');
% hold on
% plot(tempoClassicCompression, modElasClassicCompression,'ob');
% errorbar(tempoClassicCompression, modElasClassicCompression, modElasClassicCompression_Err,'ob', 'LineStyle','none');
% hold on


%% CONFIGURAÇÃO GRÁFICA DO PLOT

%Nome dos resultados:
legend ("REF-0.4-SP1","REF-0.4-SP2",...
        "REF-0.3-SP1","REF-0.3-SP2",...
        'location','southeast');
    
if plotInLog == "Sim"
    set(gca,'xscale','log')
else
end

xlabel ("Age (days)");
ylabel ("Elastic modulus (GPa)");

xlim([0 7])
ylim([0 20])
xticks([0 1 2 3 4 5 6 7])
grid on
set(gcf,'units','centimeters','position',[0,0,15,15])
set(gca,'fontsize',fontSize)
lgd.FontSize = lgdFontSize;

